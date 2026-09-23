/// 配置层：路径定位、TOML 加载校验与凭据叠加。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:test/test.dart';

/// 建临时目录；用例结束即递归删除。
Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('conatus-config');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// 把 [content] 写进临时目录的 `config.toml`，返回该文件路径。
String _writeConfig(String content) {
  final File file =
      File('${_tempDir().path}${Platform.pathSeparator}$kConfigFileName');
  file.writeAsStringSync(content);
  return file.path;
}

/// 把 [toml] 写进临时文件并加载解析，返回配置。
ConatusCodeConfig loadConfigFromToml(String toml) =>
    loadConfig(path: _writeConfig(toml));

/// 断言 [body] 抛 [ConfigException]，且消息包含 [fragment]。
void _expectConfigError(String fragment, void Function() body) {
  expect(
    body,
    throwsA(isA<ConfigException>().having(
        (ConfigException error) => error.message, 'message',
        contains(fragment))),
  );
}

void main() {
  test('常量：目录名、文件名、环境变量名', () {
    expect(kConfigDirName, '.nava');
    expect(kConfigFileName, 'config.toml');
    expect(kConfigHomeEnv, 'NAVA_HOME');
  });

  group('resolveConfigDir', () {
    test('NAVA_HOME 优先于 HOME', () {
      expect(
        resolveConfigDir(env: <String, String>{
          kConfigHomeEnv: '/tmp/custom',
          'HOME': '/tmp/home',
        }),
        '/tmp/custom',
      );
    });

    test('未设时回落到 HOME 下的目录名，空串等价于未设置', () {
      final String sep = Platform.pathSeparator;
      final String expected = '/tmp/home$sep$kConfigDirName';

      expect(
        resolveConfigDir(env: <String, String>{'HOME': '/tmp/home'}),
        expected,
      );
      expect(
        resolveConfigDir(env: <String, String>{
          kConfigHomeEnv: '   ',
          'HOME': '/tmp/home',
        }),
        expected,
      );
    });
  });

  group('resolveConfigPath', () {
    test('explicit 优先，否则配置目录下的 config.toml', () {
      final String sep = Platform.pathSeparator;
      final Map<String, String> env = <String, String>{'HOME': '/tmp/home'};

      expect(resolveConfigPath(explicit: '/tmp/a.toml', env: env), '/tmp/a.toml');
      expect(
        resolveConfigPath(env: env),
        '/tmp/home$sep$kConfigDirName$sep$kConfigFileName',
      );
    });
  });

  group('loadConfig', () {
    test('文件不存在 → 初始化模板并返回其配置', () {
      final String sep = Platform.pathSeparator;
      final String path = '${_tempDir().path}${sep}missing.toml';
      final ConatusCodeConfig config = loadConfig(path: path);

      expect(File(path).existsSync(), isTrue);
      expect(config.llm.defaultModel, isNotNull);
      expect(config.providers, isNotEmpty);
      expect(config.agent.maxSteps, 8);
      expect(config.agent.workdir, isNull);
      expect(config.agent.projectDir, '.conatus');
      expect(config.approval.mode, ApprovalMode.askWhenNeeded);
      expect(config.sandbox.enabled, isTrue);
      expect(config.sandbox.preset, SandboxPreset.workspaceWrite);
      expect(config.sandbox.allowNetwork, isFalse);
      expect(
          config.sandbox.networkAllowlist, <String>['git fetch', 'git pull']);
      expect(config.sandbox.allowedExecutables, isEmpty);
      expect(config.credentials, isEmpty);
    });

    test('合法 TOML → 逐字段映射', () {
      final ConatusCodeConfig config = loadConfig(path: _writeConfig('''
[llm]
default_model = "ark/doubao-seed"

[agent]
max_steps = 12
workdir = "/tmp/work"
project_dir = ".state"

[approval]
mode = "never_ask"

[sandbox]
preset = "danger_full_access"
allow_network = true
network_allowlist = ["api.example.com"]
allowed_executables = ["git", "dart"]

[credentials]
ARK_API_KEY = "from-file"
'''));

      expect(config.llm.defaultModel, 'ark/doubao-seed');
      expect(config.agent.maxSteps, 12);
      expect(config.agent.workdir, '/tmp/work');
      expect(config.agent.projectDir, '.state');
      expect(config.approval.mode, ApprovalMode.neverAsk);
      expect(config.sandbox.preset, SandboxPreset.dangerFullAccess);
      expect(config.sandbox.allowNetwork, isTrue);
      expect(config.sandbox.networkAllowlist, <String>['api.example.com']);
      expect(config.sandbox.allowedExecutables, <String>['git', 'dart']);
      expect(config.credentials, <String, String>{'ARK_API_KEY': 'from-file'});
    });

    test('语法错误 → ConfigException', () {
      _expectConfigError('解析失败', () {
        loadConfig(path: _writeConfig('[agent\nmax_steps = 8\n'));
      });
    });

    test('类型不符 → ConfigException', () {
      _expectConfigError('max_steps 必须是正整数', () {
        loadConfig(path: _writeConfig('[agent]\nmax_steps = "8"\n'));
      });
      _expectConfigError('[llm] 必须是表', () {
        loadConfig(path: _writeConfig('llm = "x"\n'));
      });
      _expectConfigError('allow_network 必须是布尔值', () {
        loadConfig(path: _writeConfig('[sandbox]\nallow_network = "yes"\n'));
      });
    });

    test('枚举取值非法 → ConfigException', () {
      _expectConfigError('approval.mode 取值 "sometimes" 不合法', () {
        loadConfig(path: _writeConfig('[approval]\nmode = "sometimes"\n'));
      });
      _expectConfigError('sandbox.preset 取值 "nope" 不合法', () {
        loadConfig(path: _writeConfig('[sandbox]\npreset = "nope"\n'));
      });
    });
  });

  group('ConfigCredentials', () {
    test('base 优先，配置文件兜底；keys 取并集；update 只读', () async {
      final ConatusCodeConfig config = loadConfig(
        path: _writeConfig('[credentials]\n'
            'SHARED = "file-value"\n'
            'ONLY_FILE = "file-only"\n'),
      );
      final Credentials base = InMemoryCredentials(initial: <String, String>{
        'SHARED': 'base-value',
        'ONLY_BASE': 'base-only',
      });
      final ConfigCredentials credentials =
          ConfigCredentials(config, base: base);
      addTearDown(credentials.close);

      expect(credentials.get('SHARED')?.value, 'base-value');
      expect(credentials.get('ONLY_FILE')?.value, 'file-only');
      expect(credentials.get('ONLY_BASE')?.value, 'base-only');
      expect(credentials.get('MISSING'), isNull);
      expect(
        credentials.keys,
        unorderedEquals(<String>['SHARED', 'ONLY_FILE', 'ONLY_BASE']),
      );

      await expectLater(
        credentials.update('K', 'V'),
        throwsA(isA<CredentialsException>().having(
            (CredentialsException error) => error.code, 'code', 'read-only')),
      );
    });
  });

  test('解析 [providers.*]：引号键、type 映射、oauth 子表', () {
    final ConatusCodeConfig config = loadConfigFromToml('''
[providers.arkcli-agent-plan]
api_key = "ark-1"
base_url = "https://ark.cn-beijing.volces.com/api/plan/v3"
type = "openai"

[providers."managed:kimi-code"]
api_key = ""
base_url = "https://api.kimi.com/coding/v1"
type = "kimi"
[providers."managed:kimi-code".oauth]
key = "oauth/kimi-code"
storage = "file"

[llm]
default_model = "arkcli-agent-plan/doubao-seed-2-0-lite-260215"
''');

    expect(config.providers, hasLength(2));
    final ProviderConfig ark = config.providers[0];
    expect(ark.name, 'arkcli-agent-plan');
    expect(ark.apiKey, 'ark-1');
    expect(ark.type, ProviderType.openai);

    final ProviderConfig kimi = config.providers[1];
    expect(kimi.name, 'managed:kimi-code');
    expect(kimi.apiKey, '');
    expect(kimi.type, ProviderType.kimi);
    expect(kimi.oauthKey, 'oauth/kimi-code');
    expect(config.llm.defaultModel, 'arkcli-agent-plan/doubao-seed-2-0-lite-260215');
  });

  test('default_model 格式非法抛 ConfigException', () {
    expect(
      () => loadConfigFromToml('[llm]\ndefault_model = "no-slash"'),
      throwsA(isA<ConfigException>()),
    );
    expect(
      () => loadConfigFromToml('[llm]\ndefault_model = "/model"'),
      throwsA(isA<ConfigException>()),
    );
  });

  test('未知 type 抛 ConfigException；base_url 缺失抛 ConfigException', () {
    expect(
      () => loadConfigFromToml('''
[providers.x]
base_url = "https://x"
type = "anthropic"
'''),
      throwsA(isA<ConfigException>()),
    );
    expect(
      () => loadConfigFromToml('[providers.x]\napi_key = "k"'),
      throwsA(isA<ConfigException>()),
    );
  });

  group('loadConfig 初始化', () {
    test('config.toml 不存在时写入模板并返回可解析配置', () {
      final Directory dir = Directory.systemTemp.createTempSync('nava-cfg-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final String path = '${dir.path}${Platform.pathSeparator}config.toml';

      final ConatusCodeConfig config = loadConfig(path: path);

      expect(File(path).existsSync(), isTrue);
      expect(config.providers, isNotEmpty);
      expect(config.llm.defaultModel, isNotNull);
    });

    test('config.toml 已存在时不覆盖', () {
      final Directory dir = Directory.systemTemp.createTempSync('nava-cfg-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final String path = '${dir.path}${Platform.pathSeparator}config.toml';
      File(path).writeAsStringSync('[llm]\ndefault_model = "x/y"\n');

      loadConfig(path: path);

      expect(File(path).readAsStringSync(), contains('default_model = "x/y"'));
    });
  });
}

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
    expect(kConfigDirName, '.conatus-code');
    expect(kConfigFileName, 'config.toml');
    expect(kConfigHomeEnv, 'CONATUS_CODE_HOME');
  });

  group('resolveConfigDir', () {
    test('CONATUS_CODE_HOME 优先于 HOME', () {
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
    test('文件不存在 → 全默认值', () {
      final String sep = Platform.pathSeparator;
      final ConatusCodeConfig config =
          loadConfig(path: '${_tempDir().path}${sep}missing.toml');

      expect(config.llm.provider, isNull);
      expect(config.llm.model, isNull);
      expect(config.agent.maxSteps, 8);
      expect(config.agent.workdir, isNull);
      expect(config.agent.projectDir, '.conatus');
      expect(config.approval.mode, ApprovalMode.askWhenNeeded);
      expect(config.sandbox.preset, SandboxPreset.workspaceWrite);
      expect(config.sandbox.allowNetwork, isFalse);
      expect(config.sandbox.networkAllowlist, isEmpty);
      expect(config.sandbox.allowedExecutables, isEmpty);
      expect(config.credentials, isEmpty);
    });

    test('合法 TOML → 逐字段映射', () {
      final ConatusCodeConfig config = loadConfig(path: _writeConfig('''
[llm]
provider = "ark"
model = "doubao-seed"

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

      expect(config.llm.provider, 'ark');
      expect(config.llm.model, 'doubao-seed');
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
}

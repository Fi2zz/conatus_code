/// 凭据与审批的装配级回归。
///
/// - `credential_key`：`ProviderConfig` 曾缺这个字段，而下游
///   `ProviderProfile.credentialKey` → `ProviderRegistry` → LLM 的管道一直通着，
///   于是环境变量对配置声明的 provider 完全无效，状态栏却在提示
///   「设置 ARK_API_KEY / DEEPSEEK_API_KEY」。
/// - 首次生成的 config.toml 曾以 0644 落盘（裸 `writeAsStringSync`，无 chmod）。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/providers.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _S implements LlmProvider {
  @override
  String get name => 's';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      const LlmResult(content: 'ok', provider: 's', model: 's');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

void main() {
  group('credential_key 全链路', () {
    test('解析器读出 credential_key 并进入 ProviderProfile', () {
      final ConatusCodeConfig config = loadConfig(
        path: _writeToml(
          'providers.mock.base_url = "https://x.invalid/v1"\n'
          'providers.mock.credential_key = "ARK_API_KEY"\n',
        ),
      );
      final ProviderConfig provider =
          config.providers.firstWhere((ProviderConfig p) => p.name == 'mock');
      expect(provider.credentialKey, 'ARK_API_KEY');
    });

    test('装配后 provider 的凭据键来自配置', () async {
      final Directory dir = Directory.systemTemp.createTempSync('nava-cred');
      addTearDown(() => dir.deleteSync(recursive: true));
      final ConatusTuiRuntime rt = await ConatusTuiRuntime.create(
        baseDir: dir.path,
        sessionDir: dir.path,
        memoryFile: '${dir.path}/m.json',
        workdir: dir.path,
        webTools: false,
        skills: false,
        interactive: false,
        llm: FallbackLlm(<LlmProvider>[_S()]),
        providers: <ProviderConfig>[
          const ProviderConfig(
            name: 'mock',
            baseUrl: 'https://x.invalid/v1',
            credentialKey: 'ARK_API_KEY',
          ),
        ],
        credentials: InMemoryCredentials(
          initial: <String, String>{'ARK_API_KEY': 'sk-from-env'},
        ),
        provider: 'mock',
      );
      addTearDown(rt.dispose);

      final ProviderRegistry? registry = rt.app.providers;
      expect(registry, isNotNull);
      expect(registry!.current?.credentialKey, 'ARK_API_KEY');
      // 有凭据键且凭据服务里确有该键 → 视为已配好（此前永远拿不到键）。
      expect(registry.hasKey('mock'), isTrue);
    });

    test('未声明 credential_key 时不影响既有的明文 api_key', () {
      final ConatusCodeConfig config = loadConfig(
        path: _writeToml(
          'providers.mock.base_url = "https://x.invalid/v1"\n'
          'providers.mock.api_key = "sk-inline"\n',
        ),
      );
      expect(config.providers.first.credentialKey, isEmpty);
      expect(config.providers.first.apiKey, 'sk-inline');
    });
  });

  test('首次生成的 config.toml 权限为 600', () {
    if (Platform.isWindows) return; // chmod 语义不适用。
    final Directory dir = Directory.systemTemp.createTempSync('nava-perm');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String path = '${dir.path}/config.toml';

    loadConfig(path: path);

    final FileStat stat = FileStat.statSync(path);
    // 0o600 = 384
    expect(stat.mode & 0x1FF, 0x180, reason: '应为 -rw-------');
  });
}

/// 写一份临时 config.toml，返回其路径。
String _writeToml(String body) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-toml');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String path = '${dir.path}/config.toml';
  File(path).writeAsStringSync(body);
  return path;
}

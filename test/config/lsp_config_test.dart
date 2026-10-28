/// LSP 配置解析。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-lsp-config');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

ConatusCodeConfig _load(String content) {
  final Directory dir = _tempDir();
  final File file = File(
    '${dir.path}${Platform.pathSeparator}$kConfigFileName',
  );
  file.writeAsStringSync(content);
  return loadConfig(path: file.path);
}

void main() {
  test('缺省关闭且没有服务器', () {
    final ConatusCodeConfig config = _load('');
    expect(config.lsp.enabled, isFalse);
    expect(config.lsp.servers, isEmpty);
  });

  test('解析 command / extensions / env / initialization', () {
    final ConatusCodeConfig config = _load('''
[lsp]
enabled = true

[lsp.servers.dart]
command = ["dart", "language-server", "--lsp"]
extensions = ["dart", ".DART"]

[lsp.servers.dart.env]
DART_LOG = "debug"

[lsp.servers.dart.initialization]
trace = "verbose"
''');

    expect(config.lsp.enabled, isTrue);
    final LspServerConfig server = config.lsp.servers.single;
    expect(server.name, 'dart');
    expect(server.command, <String>['dart', 'language-server', '--lsp']);
    expect(server.extensions, <String>['.dart', '.dart']);
    expect(server.env, <String, String>{'DART_LOG': 'debug'});
    expect(server.initialization, <String, Object?>{'trace': 'verbose'});
    expect(server.disabled, isFalse);
  });

  test('disabled 服务器允许空 command，但仍在配置里', () {
    final ConatusCodeConfig config = _load('''
[lsp]
enabled = true

[lsp.servers.off]
disabled = true
''');

    expect(config.lsp.servers.single.disabled, isTrue);
    expect(config.lsp.servers.single.command, isEmpty);
  });

  test('enabled 服务器缺 command 报错', () {
    expect(
      () => _load('[lsp]\nenabled = true\n[lsp.servers.dart]\nextensions = [".dart"]\n'),
      throwsA(
        isA<ConfigException>().having(
          (ConfigException error) => error.message,
          'message',
          contains('command'),
        ),
      ),
    );
  });

  test('command 不是字符串数组报错', () {
    expect(
      () => _load('[lsp]\nenabled = true\n[lsp.servers.dart]\ncommand = "dart"\n'),
      throwsA(isA<ConfigException>()),
    );
  });

  test('模板包含 LSP 示例', () {
    final Directory dir = _tempDir();
    final String path = '${dir.path}${Platform.pathSeparator}$kConfigFileName';
    loadConfig(path: path);
    final String template = File(path).readAsStringSync();
    expect(template, contains('[lsp]'));
    expect(template, contains('language-server'));
  });
}

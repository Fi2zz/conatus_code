/// LSP stdio 客户端：初始化、诊断、重开与停止。
library;

import 'dart:io';

import 'package:conatus_code/src/lsp/lsp_client.dart';
import 'package:conatus_code/src/lsp/lsp_types.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-lsp-client');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

List<String> _command(List<String> extra) => <String>[
      Platform.resolvedExecutable,
      '${Directory.current.path}/test/lsp/fixtures/fake_lsp_server.dart',
      ...extra,
    ];

LspClient _client(String workdir, {List<String> extra = const <String>[]}) =>
    LspClient(
      command: _command(extra),
      workdir: workdir,
      startTimeout: const Duration(seconds: 2),
    );

void main() {
  test('初始化并返回 fake diagnostic', () async {
    final Directory work = _tempDir();
    final File file = File('${work.path}/a.dart')..writeAsStringSync('void main() {}');
    final LspClient client = _client(work.path);
    addTearDown(client.stop);

    final List<LspDiagnostic> diagnostics = await client.diagnose(file.path);

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.path, file.path);
    expect(diagnostics.single.line, 1);
    expect(diagnostics.single.column, 1);
    expect(diagnostics.single.severity, LspSeverity.error);
    expect(diagnostics.single.message, 'fake diagnostic');
    expect(diagnostics.single.code, 'fake');
  });

  test('第二次诊断走 didChange', () async {
    final Directory work = _tempDir();
    final File file = File('${work.path}/a.dart')..writeAsStringSync('a');
    final LspClient client = _client(work.path);
    addTearDown(client.stop);

    expect(await client.diagnose(file.path), hasLength(1));
    file.writeAsStringSync('b');
    expect(await client.diagnose(file.path), hasLength(1));
  });

  test('不存在的命令抛 LspException', () async {
    final Directory work = _tempDir();
    final LspClient client = LspClient(
      command: const <String>['/no/such/lsp'],
      workdir: work.path,
      startTimeout: const Duration(seconds: 1),
    );

    expect(client.start, throwsA(isA<LspException>()));
  });

  test('server 立即崩溃不挂起', () async {
    final Directory work = _tempDir();
    final File file = File('${work.path}/a.dart')..writeAsStringSync('a');
    final LspClient client = _client(work.path, extra: <String>['--crash']);

    expect(
      () => client.diagnose(file.path),
      throwsA(isA<LspException>()),
    );
    await client.stop();
  });

  test('异常 severity 类型不崩溃', () async {
    final Directory work = _tempDir();
    final File file = File('${work.path}/a.dart')..writeAsStringSync('a');
    final LspClient client = _client(
      work.path,
      extra: <String>['--weird-severity'],
    );
    addTearDown(client.stop);

    final List<LspDiagnostic> diagnostics = await client.diagnose(file.path);
    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.severity, LspSeverity.information);
  });

  test('server 崩溃后重新启动并重新 didOpen', () async {
    final Directory work = _tempDir();
    final File file = File('${work.path}/a.dart')..writeAsStringSync('a');
    final LspClient client = _client(
      work.path,
      extra: <String>['--crash-after-open', '--open-only'],
    );
    addTearDown(client.stop);

    expect(await client.diagnose(file.path), hasLength(1));
    for (int i = 0; i < 200 && client.running; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(client.running, isFalse);
    expect(await client.diagnose(file.path), hasLength(1));
  });


  test('读取不存在的文件抛 LspException', () async {
    final Directory work = _tempDir();
    final LspClient client = _client(work.path);
    addTearDown(client.stop);

    expect(
      () => client.diagnose('${work.path}/missing.dart'),
      throwsA(isA<LspException>()),
    );
  });

  test('接受字符串 id 的响应', () async {
    final Directory work = _tempDir();
    final File file = File('${work.path}/a.dart')..writeAsStringSync('a');
    final LspClient client = _client(work.path, extra: <String>['--string-ids']);
    addTearDown(client.stop);

    expect(await client.diagnose(file.path), hasLength(1));
  });

  test('languageId 不把点目录当扩展名', () {
    expect(languageIdForPath('/tmp/a.b/file'), 'plaintext');
    expect(languageIdForPath('/tmp/.gitignore'), 'plaintext');
    expect(languageIdForPath('/tmp/a.dart'), 'dart');
    expect(languageIdForPath('/tmp/a.tsx'), 'typescript');
  });

  test('stop 杀掉忽略 shutdown 的进程', () async {
    final Directory work = _tempDir();
    final LspClient client = _client(work.path, extra: <String>['--ignore-shutdown']);
    await client.start();
    final int? pid = client.serverPid;
    expect(pid, isNotNull);
    await client.stop();

    if (!Platform.isWindows) {
      final ProcessResult result = Process.runSync('kill', <String>['-0', '$pid']);
      expect(result.exitCode, isNot(0));
    }
  });

  test('stop 可以重复调用', () async {
    final Directory work = _tempDir();
    final LspClient client = _client(work.path);
    await client.start();
    await client.stop();
    await client.stop();
    expect(client.running, isFalse);
  });
}

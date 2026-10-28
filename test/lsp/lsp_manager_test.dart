/// LSP 管理器：扩展名路由、懒启动、重启与错误状态。
library;

import 'dart:io';

import 'package:conatus_code/src/config/config_schema.dart';
import 'package:conatus_code/src/lsp/lsp_manager.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-lsp-manager');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

String _fixture() =>
    '${Directory.current.path}/test/lsp/fixtures/fake_lsp_server.dart';

LspServerConfig _server(String marker, {bool disabled = false}) =>
    LspServerConfig(
      name: 'fake',
      command: <String>[
        Platform.resolvedExecutable,
        _fixture(),
        '--marker',
        marker,
      ],
      extensions: const <String>['.dart'],
      disabled: disabled,
    );

void main() {
  test('disabled 配置不启动进程', () async {
    final Directory work = _tempDir();
    final String marker = '${work.path}/starts';
    File('${work.path}/a.dart').writeAsStringSync('a');
    final LspManager manager = LspManager(
      config: LspConfig(servers: <LspServerConfig>[_server(marker)]),
      workdir: work.path,
    );

    expect(await manager.diagnose('${work.path}/a.dart'), isEmpty);
    expect(File(marker).existsSync(), isFalse);
    await manager.close();
  });

  test('.dart 懒启动并复用同一个 client', () async {
    final Directory work = _tempDir();
    final String marker = '${work.path}/starts';
    final File file = File('${work.path}/a.dart')..writeAsStringSync('a');
    final LspManager manager = LspManager(
      config: LspConfig(
        enabled: true,
        servers: <LspServerConfig>[_server(marker)],
      ),
      workdir: work.path,
    );
    addTearDown(manager.close);

    expect(await manager.diagnose(file.path), hasLength(1));
    expect(await manager.diagnose(file.path), hasLength(1));
    expect(File(marker).readAsLinesSync(), hasLength(1));
    expect(manager.statuses().single.state, 'running');
    expect(manager.statuses().single.diagnosticCount, 1);
  });

  test('不匹配扩展名不启动', () async {
    final Directory work = _tempDir();
    final String marker = '${work.path}/starts';
    File('${work.path}/a.txt').writeAsStringSync('a');
    final LspManager manager = LspManager(
      config: LspConfig(
        enabled: true,
        servers: <LspServerConfig>[_server(marker)],
      ),
      workdir: work.path,
    );
    addTearDown(manager.close);

    expect(await manager.diagnose('${work.path}/a.txt'), isEmpty);
    expect(File(marker).existsSync(), isFalse);
  });

  test('启动失败标记 error 并返回空诊断', () async {
    final Directory work = _tempDir();
    final File file = File('${work.path}/a.dart')..writeAsStringSync('a');
    final LspManager manager = LspManager(
      config: const LspConfig(
        enabled: true,
        servers: <LspServerConfig>[
          LspServerConfig(
            name: 'missing',
            command: <String>['/no/such/lsp'],
            extensions: <String>['.dart'],
          ),
        ],
      ),
      workdir: work.path,
    );
    addTearDown(manager.close);

    expect(await manager.diagnose(file.path), isEmpty);
    expect(manager.statuses().single.state, 'error');
    expect(manager.statuses().single.error, isNotNull);
  });

  test('restart 会重新启动 server', () async {
    final Directory work = _tempDir();
    final String marker = '${work.path}/starts';
    final File file = File('${work.path}/a.dart')..writeAsStringSync('a');
    final LspManager manager = LspManager(
      config: LspConfig(
        enabled: true,
        servers: <LspServerConfig>[_server(marker)],
      ),
      workdir: work.path,
    );
    addTearDown(manager.close);

    await manager.diagnose(file.path);
    await manager.restart();
    expect(manager.statuses().single.state, 'idle');
    await manager.diagnose(file.path);
    expect(File(marker).readAsLinesSync(), hasLength(2));
  });

  test('close 停止所有 client', () async {
    final Directory work = _tempDir();
    final String marker = '${work.path}/starts';
    final File file = File('${work.path}/a.dart')..writeAsStringSync('a');
    final LspManager manager = LspManager(
      config: LspConfig(
        enabled: true,
        servers: <LspServerConfig>[_server(marker)],
      ),
      workdir: work.path,
    );

    await manager.diagnose(file.path);
    await manager.close();
    expect(manager.statuses().single.state, 'idle');
  });
}

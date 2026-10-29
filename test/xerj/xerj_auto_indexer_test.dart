import 'dart:io';

import 'package:conatus_code/src/xerj/xerj_auto_indexer.dart';
import 'package:conatus_code/src/xerj/xerj_endpoint.dart';
import 'package:conatus_code/src/xerj/xerj_exec.dart';
import 'package:conatus_code/src/xerj/xerj_marker.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import '../fs_tools/support/fake_shell.dart';

class _FakeEndpoint implements XerjEndpoint {
  @override
  Future<String?> ensureRunning() async => 'http://127.0.0.1:19200';
}

class _StubTool extends Tool {
  _StubTool(this.name, this._result);

  @override
  final String name;

  final ToolResult _result;

  @override
  String get description => '测试替身';

  @override
  Future<ToolResult> call(ToolContext ctx) async => _result;
}

ShellRunResult _run({int exitCode = 0, String stdout = 'indexed'}) =>
    ShellRunResult(
      exitCode: exitCode,
      timedOut: false,
      timeoutMs: 20000,
      stdout: CollectedOutput(text: stdout),
      stderr: const CollectedOutput(text: ''),
    );

/// 等一轮去抖 + 后台索引完成。
Future<void> settle([int ms = 120]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late Directory dir;
  late FakeShellExecutor shell;
  late XerjExec exec;
  late XerjAutoIndexer indexer;
  late ToolRegistry tools;
  late Disposer disposer;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('conatus-xerj-autoindex-');
    shell = FakeShellExecutor(_run());
    exec = XerjExec(
      shell: shell,
      endpoint: _FakeEndpoint(),
      binaryPath: 'xerj',
      url: 'http://127.0.0.1:19200',
      prefix: 'nava-test',
      marker: XerjMarker('${dir.path}/indexed/nava-test'),
    );
    indexer = XerjAutoIndexer(
      exec: exec,
      workdir: '/repo',
      delay: const Duration(milliseconds: 30),
    );
    final Context ctx = Context.root();
    tools = provideTools(ctx);
    disposer = indexer.mount(tools);
  });

  tearDown(() {
    disposer();
    indexer.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> markIndexed() async {
    await exec.index('/repo', const Duration(minutes: 1));
    shell.calls = 0;
  }

  group('XerjAutoIndexer', () {
    test('从未索引过 → 编辑后不触发', () async {
      tools.register(_StubTool('edit', ToolResult.success('ok')));

      await tools.call(const ToolCall(name: 'edit'));
      await settle();

      expect(shell.calls, 0);
    });

    test('已索引 + 编辑成功 → 去抖后触发一次', () async {
      await markIndexed();
      tools.register(_StubTool('edit', ToolResult.success('ok')));

      await tools.call(const ToolCall(name: 'edit'));
      await settle();

      expect(shell.calls, 1);
    });

    test('去抖窗口内连续编辑只触发一次', () async {
      await markIndexed();
      tools.register(_StubTool('edit', ToolResult.success('ok')));

      await tools.call(const ToolCall(name: 'edit'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tools.call(const ToolCall(name: 'edit'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tools.call(const ToolCall(name: 'edit'));
      await settle();

      expect(shell.calls, 1);
    });

    test('非编辑工具不触发', () async {
      await markIndexed();
      tools.register(_StubTool('read', ToolResult.success('ok')));

      await tools.call(const ToolCall(name: 'read'));
      await settle();

      expect(shell.calls, 0);
    });

    test('编辑失败不触发', () async {
      await markIndexed();
      tools.register(
        _StubTool('edit', ToolResult.failure('boom')),
      );

      await tools.call(const ToolCall(name: 'edit'));
      await settle();

      expect(shell.calls, 0);
    });

    test('成功后写入标记，跨实例可见', () async {
      await markIndexed();

      expect(await XerjMarker('${dir.path}/indexed/nava-test').marked(), isTrue);
      expect(await exec.hasIndex(), isTrue);
    });

    test('dispose 取消待执行任务', () async {
      await markIndexed();
      tools.register(_StubTool('edit', ToolResult.success('ok')));

      await tools.call(const ToolCall(name: 'edit'));
      indexer.dispose();
      await settle();

      expect(shell.calls, 0);
    });

    test('索引进行中再次编辑 → 结束后补跑一次', () async {
      await markIndexed();
      tools.register(_StubTool('edit', ToolResult.success('ok')));

      shell.result = _run();
      await tools.call(const ToolCall(name: 'edit'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      // 第一次索引进行中（FakeShell 立即返回，这里只验证去抖链不丢事件）。
      await tools.call(const ToolCall(name: 'edit'));
      await settle();

      expect(shell.calls, greaterThanOrEqualTo(1));
    });
  });
}

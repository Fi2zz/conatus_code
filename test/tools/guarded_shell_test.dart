/// 命令审查装饰器：deny / review 都映射成正常结果，不抛异常。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 只记录调用、返回固定结果的执行器替身。
class _RecordingShell implements ShellExecutor {
  int calls = 0;

  @override
  ShellExecSpec resolve(ShellExecRequest request) => ShellExecSpec(
    command: request.command,
    workdir: request.workdir ?? '/tmp',
    timeoutMs: request.timeoutMs ?? 1000,
    stdoutMaxBytes: request.stdoutMaxBytes ?? 1024,
  );

  @override
  Future<ShellRunResult> run(ShellExecSpec spec) async {
    calls++;
    return const ShellRunResult(
      exitCode: 0,
      timedOut: false,
      timeoutMs: 1000,
      stdout: CollectedOutput(text: 'ok'),
      stderr: CollectedOutput(text: ''),
    );
  }

  @override
  Future<ShellProcess> start(ShellExecSpec spec) async {
    calls++;
    return RejectedShellProcess('unused');
  }
}

ShellExecSpec _spec(String command) => ShellExecSpec(
  command: command,
  workdir: '/tmp',
  timeoutMs: 1000,
  stdoutMaxBytes: 1024,
);

void main() {
  late _RecordingShell inner;
  late GuardedShellExecutor shell;

  setUp(() {
    inner = _RecordingShell();
    shell = GuardedShellExecutor(inner: inner, policy: CommandPolicy());
  });

  test('allow → 透传给内部执行器', () async {
    final ShellRunResult result = await shell.run(_spec('ls -la'));
    expect(inner.calls, 1);
    expect(result.exitCode, 0);
  });

  test('deny → 不执行，理由进 stderr', () async {
    final ShellRunResult result = await shell.run(_spec('rm -rf /'));
    expect(inner.calls, 0);
    expect(result.exitCode, isNull);
    expect(result.stderr.text, contains('拒绝'));
  });

  test('review 无复核回调 → 按拒绝（fail-closed）', () async {
    final ShellRunResult result = await shell.run(
      _spec('echo hi && git status'),
    );
    expect(inner.calls, 0);
    expect(result.stderr.text, contains('拒绝'));
  });

  test('review 被拒 → 不执行', () async {
    shell.reviewPrompter = (String command, String reason) async => false;
    final ShellRunResult result = await shell.run(
      _spec('echo hi && git status'),
    );
    expect(inner.calls, 0);
    expect(result.stderr.text, contains('未获'));
  });

  test('review 获批 → 照常执行', () async {
    shell.reviewPrompter = (String command, String reason) async => true;
    final ShellRunResult result = await shell.run(
      _spec('echo hi && git status'),
    );
    expect(inner.calls, 1);
    expect(result.exitCode, 0);
  });

  test('复核回调抛错 → 按拒绝', () async {
    shell.reviewPrompter = (String command, String reason) async =>
        throw StateError('ui gone');
    final ShellRunResult result = await shell.run(
      _spec('echo hi && git status'),
    );
    expect(inner.calls, 0);
    expect(result.stderr.text, contains('未获'));
  });

  test('start 被拒绝 → 假进程句柄给出理由', () async {
    final ShellProcess process = await shell.start(_spec('rm -rf /'));
    expect(inner.calls, 0);
    expect(process.status, ShellProcessStatus.completed);
    expect(process.readOutput().delta, contains('拒绝'));
  });
}

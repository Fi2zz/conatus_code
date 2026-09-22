import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  test('run 拒绝：exitCode null 且 stderr 带理由', () async {
    final RejectingShellExecutor shell = RejectingShellExecutor('后端不可用');
    final ShellExecSpec spec =
        shell.resolve(const ShellExecRequest(command: 'ls'));

    final ShellRunResult result = await shell.run(spec);

    expect(result.exitCode, isNull);
    expect(result.timedOut, isFalse);
    expect(result.stdout.text, isEmpty);
    expect(result.stderr.text, contains('后端不可用'));
  });

  test('start 返回已完成且 exitCode null 的进程句柄', () async {
    final RejectingShellExecutor shell = RejectingShellExecutor('后端不可用');

    final ShellProcess process = await shell
        .start(shell.resolve(const ShellExecRequest(command: 'ls')));

    expect(process.status, ShellProcessStatus.completed);
    expect(process.exitCode, isNull);
    expect(process.readOutput().delta, contains('后端不可用'));
    expect(process.kill(), isFalse);
  });
}

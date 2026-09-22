import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import '../coding/support/fake_shell.dart';

ShellRunResult _result({
  int? exitCode = 0,
  bool timedOut = false,
  String stdout = '',
  String stderr = '',
}) =>
    ShellRunResult(
      exitCode: exitCode,
      timedOut: timedOut,
      timeoutMs: 1000,
      stdout: CollectedOutput(text: stdout),
      stderr: CollectedOutput(text: stderr),
    );

ToolContext _context(String name, Map<String, Object?> args) =>
    ToolContext(ToolCall(name: name, arguments: args));

void main() {
  test('exit 0 → success，content 为 stdout，value 附字段', () async {
    final FakeShellExecutor shell = FakeShellExecutor(_result(stdout: 'hello\n'));
    final RunCommandTool tool = RunCommandTool(shell: shell);

    final ToolResult result = await tool.call(
        _context('run_command', <String, Object?>{'command': 'echo hello'}));

    expect(result.isError, isFalse);
    expect(result.content, 'hello\n');
    final Map<String, Object?> value = result.value! as Map<String, Object?>;
    expect(value['exit_code'], 0);
    expect(value['stderr'], '');
    expect(value['timeout_ms'], 1000);
  });

  test('非零退出 → COMMAND_FAILED，content 合并两路输出', () async {
    final FakeShellExecutor shell =
        FakeShellExecutor(_result(exitCode: 1, stdout: 'out', stderr: 'err'));
    final RunCommandTool tool = RunCommandTool(shell: shell);

    final ToolResult result = await tool.call(
        _context('run_command', <String, Object?>{'command': 'false'}));

    expect(result.isError, isTrue);
    expect(result.error!.code, 'COMMAND_FAILED');
    expect(result.content, contains('out'));
    expect(result.content, contains('err'));
  });

  test('exitCode null（被拒绝/后端故障）→ COMMAND_FAILED', () async {
    final FakeShellExecutor shell = FakeShellExecutor(_result(exitCode: null));
    final RunCommandTool tool = RunCommandTool(shell: shell);

    final ToolResult result = await tool.call(
        _context('run_command', <String, Object?>{'command': 'x'}));

    expect(result.isError, isTrue);
    expect(result.error!.code, 'COMMAND_FAILED');
  });

  test('超时 → TOOL_TIMEOUT', () async {
    final FakeShellExecutor shell =
        FakeShellExecutor(_result(exitCode: null, timedOut: true));
    final RunCommandTool tool = RunCommandTool(shell: shell);

    final ToolResult result = await tool.call(
        _context('run_command', <String, Object?>{'command': 'sleep 5'}));

    expect(result.isError, isTrue);
    expect(result.error!.code, 'TOOL_TIMEOUT');
    expect(result.content, contains('超时'));
  });

  test('执行器抛异常 → SHELL_ERROR', () async {
    final FakeShellExecutor shell = FakeShellExecutor(); // run 对 null 抛错
    final RunCommandTool tool = RunCommandTool(shell: shell);

    final ToolResult result = await tool.call(
        _context('run_command', <String, Object?>{'command': 'x'}));

    expect(result.isError, isTrue);
    expect(result.error!.code, 'SHELL_ERROR');
  });

  test('timeout_ms / cwd 透传到 resolve', () async {
    final FakeShellExecutor shell = FakeShellExecutor(_result(stdout: 'x'));
    final RunCommandTool tool = RunCommandTool(shell: shell);

    await tool.call(_context('run_command', <String, Object?>{
      'command': 'sleep 1',
      'cwd': 'sub',
      'timeout_ms': 500,
    }));

    expect(shell.lastRequest!.timeoutMs, 500);
    expect(shell.lastRequest!.workdir, 'sub');
  });

  test('run_tests 缺省 dart test', () async {
    final FakeShellExecutor shell = FakeShellExecutor(_result(stdout: 'ok'));
    final RunTestsTool tool = RunTestsTool(shell: shell);

    final ToolResult result =
        await tool.call(_context('run_tests', <String, Object?>{}));

    expect(result.isError, isFalse);
    expect(shell.lastRequest!.command, 'dart test');
  });
}

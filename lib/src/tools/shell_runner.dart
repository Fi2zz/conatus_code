/// 命令执行工具的共享逻辑：resolve + run 并映射为 [ToolResult]。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 执行命令并映射为工具结果。
///
/// exit 0 → success（content 为 stdout，value 附 stderr/exitCode/timeout）；
/// 超时 → `TOOL_TIMEOUT`；非零或 null → `COMMAND_FAILED`（content 合并两路）；
/// 执行器抛异常 → `SHELL_ERROR`。
Future<ToolResult> runShellCommand(
  ShellExecutor shell,
  String command, {
  String? cwd,
  int? timeoutMs,
}) async {
  final ShellExecSpec spec = shell.resolve(
    ShellExecRequest(command: command, workdir: cwd, timeoutMs: timeoutMs),
  );
  final ShellRunResult result;
  try {
    result = await shell.run(spec);
  } catch (e) {
    return ToolResult.failure(
      '命令执行失败：$e',
      error: ToolError('SHELL_ERROR', '$e'),
    );
  }
  if (result.timedOut) {
    return ToolResult.failure(
      '命令超时（${result.timeoutMs}ms）',
      error: const ToolError('TOOL_TIMEOUT', '命令超时'),
    );
  }
  final String stdout = result.stdout.text;
  final String stderr = result.stderr.text;
  final int? exitCode = result.exitCode;
  if (exitCode == 0) {
    return ToolResult.success(
      stdout.isEmpty ? '（无输出）' : stdout,
      value: <String, Object?>{
        'exit_code': 0,
        'stdout': stdout,
        'stderr': stderr,
        'timeout_ms': result.timeoutMs,
      },
    );
  }
  return ToolResult.failure(
    _merged(stdout, stderr, exitCode),
    error: ToolError('COMMAND_FAILED', 'exit ${exitCode ?? 'null'}'),
  );
}

/// 合并两路输出；都为空时给出退出码说明。
String _merged(String stdout, String stderr, int? exitCode) {
  final String body = stdout.isEmpty
      ? stderr
      : stderr.isEmpty
          ? stdout
          : '$stdout\n$stderr';
  if (body.isNotEmpty) return body;
  return '命令失败（exit ${exitCode ?? 'null'}）';
}

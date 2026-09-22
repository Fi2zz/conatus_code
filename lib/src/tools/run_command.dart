import 'package:conatus_foundation/conatus_foundation.dart';

import 'shell_runner.dart';

/// 在沙箱中执行一条命令的工具。
class RunCommandTool extends Tool {
  const RunCommandTool({required ShellExecutor shell}) : _shell = shell;

  final ShellExecutor _shell;

  @override
  String get name => 'run_command';

  @override
  String get description => '在沙箱中执行一条命令，返回退出码与输出。';

  @override
  ToolRisk get riskLevel => ToolRisk.high;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('command', required: true, description: '要执行的命令'),
        ParamSpec.string('cwd', description: '工作目录（相对沙箱根）'),
        ParamSpec.integer('timeout_ms', description: '超时（毫秒）'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String command = ctx.str('command');
    final String? cwd = ctx.string('cwd');
    final int? timeoutMs = ctx.integer('timeout_ms');
    return runShellCommand(_shell, command, cwd: cwd, timeoutMs: timeoutMs);
  }
}

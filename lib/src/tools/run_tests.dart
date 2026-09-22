import 'package:conatus_foundation/conatus_foundation.dart';

import 'shell_runner.dart';

/// 在沙箱中运行测试的工具。
class RunTestsTool extends Tool {
  const RunTestsTool({required ShellExecutor shell}) : _shell = shell;

  final ShellExecutor _shell;

  @override
  String get name => 'run_tests';

  @override
  String get description => '在沙箱中运行测试（默认 dart test）。';

  @override
  ToolRisk get riskLevel => ToolRisk.high;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('test_cmd', description: '测试命令，默认 dart test'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String command = ctx.string('test_cmd') ?? 'dart test';
    return runShellCommand(_shell, command);
  }
}

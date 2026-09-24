/// 后台任务工具：启动 / 列表 / 读输出 / 终止。
///
/// 服务依赖 `'backgroundTasks'`（[BackgroundTaskService]），由装配方在根上下文
/// 提供后经 [provideBackgroundTools] 注入。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'background_tasks.dart';

/// 后台启动一条命令（high 风险，走审批）。
class RunCommandBackgroundTool extends Tool {
  RunCommandBackgroundTool({required BackgroundTaskService service})
      : _service = service;

  final BackgroundTaskService _service;

  @override
  String get name => 'run_command_background';

  @override
  String get description => '在沙箱中后台启动一条命令（不阻塞对话），返回任务 id；'
      '用 list_background_tasks / background_output 查看。';

  @override
  ToolRisk get riskLevel => ToolRisk.high;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('command', required: true, description: '要执行的命令'),
        ParamSpec.string('cwd', description: '工作目录（相对沙箱根）'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String command = ctx.str('command');
    final String? cwd = ctx.string('cwd');
    try {
      final String id = await _service.start(command, cwd: cwd);
      return ToolResult.success('后台任务 $id 已启动：$command\n'
          '用 list_background_tasks / background_output 查看进度。');
    } on BackgroundException catch (error) {
      return ToolResult.failure(
        error.message,
        error: ToolError(error.code, error.message),
      );
    }
  }
}

/// 列出全部后台任务。
class ListBackgroundTasksTool extends Tool {
  ListBackgroundTasksTool({required BackgroundTaskService service})
      : _service = service;

  final BackgroundTaskService _service;

  @override
  String get name => 'list_background_tasks';

  @override
  String get description => '列出全部后台任务（状态 / 退出码 / 耗时 / 输出字节）。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => const <ParamSpec>[];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final List<BackgroundTaskView> tasks = _service.list();
    if (tasks.isEmpty) return ToolResult.success('当前没有后台任务。');
    final StringBuffer buffer = StringBuffer('后台任务（${tasks.length}）：');
    for (final BackgroundTaskView task in tasks) {
      buffer.write('\n  ${task.id} [${task.status.name}] ${task.command}'
          '（${_seconds(task.elapsedMs)}，输出 ${task.outputBytes}B）');
    }
    return ToolResult.success(buffer.toString());
  }

  static String _seconds(int ms) => ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';
}

/// 读取某后台任务的累计输出。
class BackgroundOutputTool extends Tool {
  BackgroundOutputTool({required BackgroundTaskService service})
      : _service = service;

  final BackgroundTaskService _service;

  @override
  String get name => 'background_output';

  @override
  String get description => '读取某后台任务的累计输出（增量并入）。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('task_id', required: true, description: '后台任务 id（bg-<n>）'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String id = ctx.str('task_id');
    try {
      final String output = _service.output(id);
      if (output.isEmpty) return ToolResult.success('（尚无输出）');
      return ToolResult.success(output.length > kBackgroundOutputLimit
          ? output.substring(output.length - kBackgroundOutputLimit)
          : output);
    } on BackgroundException catch (error) {
      return ToolResult.failure(
        error.message,
        error: ToolError(error.code, error.message),
      );
    }
  }
}

/// 终止某后台任务。
class BackgroundKillTool extends Tool {
  BackgroundKillTool({required BackgroundTaskService service})
      : _service = service;

  final BackgroundTaskService _service;

  @override
  String get name => 'background_kill';

  @override
  String get description => '终止某后台任务。';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('task_id', required: true, description: '后台任务 id（bg-<n>）'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String id = ctx.str('task_id');
    try {
      final bool killed = _service.kill(id);
      return ToolResult.success(killed ? '已终止后台任务 $id。' : '后台任务 $id 已结束。');
    } on BackgroundException catch (error) {
      return ToolResult.failure(
        error.message,
        error: ToolError(error.code, error.message),
      );
    }
  }
}

/// 工具结果里展示的输出上限（取尾部）。
const int kBackgroundOutputLimit = 8000;

/// 注册 4 个后台任务工具。
List<Tool> provideBackgroundTools(
  Context ctx, {
  required BackgroundTaskService service,
}) {
  final ToolRegistry registry = ctx.tools;
  final List<Tool> tools = <Tool>[
    RunCommandBackgroundTool(service: service),
    ListBackgroundTasksTool(service: service),
    BackgroundOutputTool(service: service),
    BackgroundKillTool(service: service),
  ];
  for (final Tool tool in tools) {
    ctx.effect(() => registry.register(tool));
  }
  return tools;
}

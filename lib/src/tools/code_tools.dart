import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'git_tools.dart';
import 'git_write_tools.dart';
import 'run_command.dart';
import 'run_tests.dart';

/// 注册 conatus_code 新增的工具（git 系列、`bash`、`run_tests`），返回已注册
/// 的工具。
///
/// 依赖：
/// - `'tools'`：工具注册（必需）
/// - `'shell'`：子进程执行（git 工具必需；缺失时只注册 `bash` 与 `run_tests`）
///
/// 文件读写与搜索工具由 `provideFsTools` 负责，不在本函数内注册。注册撤销由
/// 上下文生命周期统一管理。
List<Tool> provideCodeTools(
  Context ctx, {
  ToolRegistry? tools,
  ShellExecutor? shell,
}) {
  final ToolRegistry registry = tools ?? ctx.tools;
  final ShellExecutor? resolvedShell = shell ?? ctx.get<ShellExecutor>('shell');
  final List<Tool> registered = <Tool>[];
  if (resolvedShell != null) {
    registered.addAll(<Tool>[
      GitStatusTool(shell: resolvedShell),
      GitDiffTool(shell: resolvedShell),
      GitAddTool(shell: resolvedShell),
      GitBranchTool(shell: resolvedShell),
      GitStashTool(shell: resolvedShell),
      GitCommitTool(shell: resolvedShell),
      RunCommandTool(shell: resolvedShell),
      RunTestsTool(shell: resolvedShell),
    ]);
  }
  for (final Tool tool in registered) {
    ctx.effect(() => registry.register(tool));
  }
  return registered;
}

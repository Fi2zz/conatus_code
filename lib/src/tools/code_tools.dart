import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'apply_patch.dart';
import 'git_tools.dart';
import 'list_files.dart';

/// 注册 conatus_code 新增的工具，返回已注册的工具。
///
/// 依赖：
/// - `'tools'`：工具注册（必需）
/// - `'fs'`：文件系统接缝（必需，`list_files` 用）
/// - `'shell'`：子进程执行（git 工具必需；缺失时只注册 `list_files` 与 `apply_patch`）
///
/// 注册撤销由上下文生命周期统一管理。
List<Tool> provideCodeTools(
  Context ctx, {
  ToolRegistry? tools,
  FileSystem? fs,
  ShellExecutor? shell,
}) {
  final ToolRegistry registry = tools ?? ctx.tools;
  final FileSystem resolvedFs = fs ?? ctx.require<FileSystem>('fs');
  final ShellExecutor? resolvedShell = shell ?? ctx.get<ShellExecutor>('shell');
  final List<Tool> registered = <Tool>[
    ListFilesTool(fs: resolvedFs),
    ApplyPatchTool(fs: resolvedFs),
  ];
  if (resolvedShell != null) {
    registered.addAll(<Tool>[
      GitStatusTool(shell: resolvedShell),
      GitDiffTool(shell: resolvedShell),
    ]);
  }
  for (final Tool tool in registered) {
    ctx.effect(() => registry.register(tool));
  }
  return registered;
}

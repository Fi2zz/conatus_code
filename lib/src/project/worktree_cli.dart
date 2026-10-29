/// `nava worktree` 子命令。
library;

import 'dart:io';

import 'project_registry.dart';
import 'worktree_service.dart';

Future<int> runWorktreeCli(
  List<String> args, {
  Map<String, String>? env,
  String? workdir,
}) async {
  final String root = workdir ?? Directory.current.path;
  final ProjectRegistry registry;
  try {
    registry = ProjectRegistry.open(env: env);
  } catch (error) {
    stderr.writeln('项目注册表错误：$error');
    return 2;
  }
  final WorktreeService service = WorktreeService(
    registry: registry,
    workdir: root,
  );
  try {
    if (args.isEmpty || args.first == 'list') {
      for (final WorkspaceInfo item in service.list()) {
        stdout.writeln(
          '${item.strategy ?? 'user'}  ${item.worktreePath}',
        );
      }
      return 0;
    }
    if (args.first == 'new') {
      if (args.length < 2) {
        stderr.writeln('用法：nava worktree new <名字> [branch]');
        return 2;
      }
      final WorktreeCreateResult result = await service.create(
        args[1],
        branch: args.length > 2 ? args[2] : null,
      );
      stdout.writeln(
        '已创建 ${result.path}（分支 ${result.branch}）',
      );
      return 0;
    }
    if (args.first == 'remove') {
      if (args.length < 2 || !args.contains('--purge')) {
        stderr.writeln('用法：nava worktree remove <名字> --purge');
        return 2;
      }
      await service.remove(args[1], purge: true);
      stdout.writeln('已删除 ${args[1]}');
      return 0;
    }
    stderr.writeln('用法：nava worktree list|new|remove');
    return 2;
  } catch (error) {
    stderr.writeln('worktree 操作失败：$error');
    return 2;
  } finally {
    registry.close();
  }
}

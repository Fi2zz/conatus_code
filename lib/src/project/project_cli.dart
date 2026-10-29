/// `nava project` 子命令：修复注册表。
library;

import 'dart:io';

import 'project_registry.dart';
import 'project_repair.dart';

Future<int> runProjectCli(
  List<String> args, {
  Map<String, String>? env,
}) async {
  final bool purge = args.contains('--purge');
  final List<String> positional = args
      .where((String arg) => arg != '--purge')
      .toList();
  if (positional.length != 1 ||
      (positional.first != 'repair' && positional.first != 'prune') ||
      (purge && positional.first != 'prune')) {
    stderr.writeln('用法：nava project repair|prune [--purge]');
    return 2;
  }
  if (positional.first == 'prune') {
    final ProjectRegistry registry = ProjectRegistry.open(env: env);
    try {
      final int archived = registry.archiveMissing();
      final int purged = purge ? registry.purgeArchived() : 0;
      stdout.writeln(
        '已归档 $archived 个失效项目'
        '${purge ? '，删除 $purged 个归档项目' : ''}。',
      );
      return 0;
    } finally {
      registry.close();
    }
  }
  final ProjectRepairReport report = repairProjectRegistry(env: env);
  stdout.writeln(
    '项目注册表修复完成：恢复 ${report.restored} 个 worktree，'
    '跳过 ${report.skipped} 个。',
  );
  if (report.backupPath != null) {
    stdout.writeln('损坏的数据库已备份到：${report.backupPath}');
  }
  return 0;
}

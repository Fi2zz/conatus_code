/// `nava project` 子命令：修复注册表。
library;

import 'dart:io';

import 'project_repair.dart';

Future<int> runProjectCli(
  List<String> args, {
  Map<String, String>? env,
}) async {
  if (args.length != 1 || args.first != 'repair') {
    stderr.writeln('用法：nava project repair');
    return 2;
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

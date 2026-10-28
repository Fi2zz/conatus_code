/// 项目注册表修复：从工作区 sidecar 重建缺失/损坏的 projects.db。
library;

import 'dart:io';

import '../config/config_path.dart';
import 'project_database.dart';
import 'project_registry.dart';

/// 修复结果。
class ProjectRepairReport {
  const ProjectRepairReport({
    required this.restored,
    required this.skipped,
    this.backupPath,
  });

  final int restored;
  final int skipped;
  final String? backupPath;

  bool get backedUp => backupPath != null;
}

/// 扫描 `workspaces/*/workspace.json` 并重建注册表。
///
/// DB 损坏时先改名为 `projects.db.corrupt-<ms>`（WAL/SHM 一并改名），
/// 再创建新库。没有 sidecar 的旧目录无法恢复，计入 [skipped]。
ProjectRepairReport repairProjectRegistry({
  String? dbPath,
  String? workspacesDir,
  Map<String, String>? env,
}) {
  final String home = resolveConfigDir(env: env);
  final String sep = Platform.pathSeparator;
  final String path = dbPath ?? '$home${sep}projects.db';
  final String root = workspacesDir ?? '$home${sep}workspaces';
  String? backup;

  ProjectDatabase database;
  try {
    database = ProjectDatabase.open(path);
  } on StateError {
    if (File(path).existsSync()) {
      backup = '$path.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      for (final String suffix in <String>['', '-wal', '-shm']) {
        final File source = File('$path$suffix');
        if (source.existsSync()) {
          source.renameSync('$backup$suffix');
        }
      }
    }
    database = ProjectDatabase.open(path);
  }

  int restored = 0;
  int skipped = 0;
  try {
    Directory(root).createSync(recursive: true);
    _writeMissingSidecars(database, root);
    for (final FileSystemEntity entity in Directory(root).listSync()) {
      if (entity is! Directory) continue;
      final WorkspaceInfo? info = readWorkspaceSidecar(entity.path);
      if (info == null) {
        skipped++;
        continue;
      }
      try {
        database.saveProject(
          id: info.projectId,
          name: info.projectName,
        );
        database.saveWorktree(
          id: info.worktreeId,
          projectId: info.projectId,
          path: info.worktreePath,
          name: entity.path.split(sep).last,
          dirName: entity.path.split(sep).last,
        );
        restored++;
      } on StateError {
        skipped++;
      }
    }
  } finally {
    database.close();
  }
  return ProjectRepairReport(
    restored: restored,
    skipped: skipped,
    backupPath: backup,
  );
}

/// 给 DB 里已有、但还没写 sidecar 的工作区补一份，便于下次恢复。
void _writeMissingSidecars(ProjectDatabase database, String root) {
  for (final WorktreeRecord worktree in database.worktrees()) {
    final String dir = '$root${Platform.pathSeparator}${worktree.dirName}';
    if (!Directory(dir).existsSync()) continue;
    if (File('$dir${Platform.pathSeparator}$kWorkspaceSidecar').existsSync()) {
      continue;
    }
    writeWorkspaceSidecar(
      WorkspaceInfo(
        projectId: worktree.projectId,
        projectName: database.project(worktree.projectId)?.name ?? worktree.name,
        worktreeId: worktree.id,
        worktreePath: worktree.path,
        dataDir: dir,
      ),
    );
  }
}

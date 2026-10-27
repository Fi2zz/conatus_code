/// 项目注册表：把项目身份落到 SQLite，并分配独立工作区目录。
library;

import 'dart:io';

import '../config/config_path.dart';
import '../read_only_paths.dart';
import 'project_database.dart';
import 'project_identity.dart';
import 'project_paths.dart';

/// 当前 worktree 的项目信息。
class WorkspaceInfo {
  const WorkspaceInfo({
    required this.projectId,
    required this.projectName,
    required this.worktreeId,
    required this.worktreePath,
    required this.dataDir,
  });

  final String projectId;
  final String projectName;
  final String worktreeId;
  final String worktreePath;
  final String dataDir;

  /// `/project` 等界面使用的短 ID。
  String get projectShortId => projectId.substring(0, 8);
}

/// 项目/工作区注册表。
class ProjectRegistry {
  ProjectRegistry({required this.database, required this.workspacesDir});

  /// 按 `NAVA_HOME` 打开默认 DB 与工作区根。
  factory ProjectRegistry.open({
    String? dbPath,
    String? workspacesDir,
    Map<String, String>? env,
  }) {
    final String home = resolveConfigDir(env: env);
    final String sep = Platform.pathSeparator;
    final String resolvedDbPath = dbPath ?? '$home${sep}projects.db';
    final String resolvedWorkspaces =
        workspacesDir ?? '$home${sep}workspaces';
    if (readOnlyWritePath(resolvedDbPath) ||
        readOnlyWritePath(resolvedWorkspaces)) {
      throw StateError(kReadOnlyPathMessage);
    }
    final ProjectRegistry registry = ProjectRegistry(
      database: ProjectDatabase.open(resolvedDbPath),
      workspacesDir: resolvedWorkspaces,
    );
    Directory(registry.workspacesDir).createSync(recursive: true);
    if (!Platform.isWindows) {
      Process.runSync('chmod', <String>['700', registry.workspacesDir]);
    }
    return registry;
  }

  final ProjectDatabase database;
  final String workspacesDir;

  /// 解析并登记 [workdir]；[dataDirOverride] 用于显式 `project_dir`。
  WorkspaceInfo resolve(String workdir, {String? dataDirOverride}) {
    final ProjectIdentity identity = resolveProjectIdentity(workdir);
    final String launchDir = _canonical(workdir);
    final ProjectRecord? existingProject = database.project(identity.projectId);
    final String projectName = existingProject?.name ?? identity.name;
    if (existingProject == null) {
      database.saveProject(
        id: identity.projectId,
        name: projectName,
        vcs: identity.vcs,
        remote: identity.remote,
      );
    } else {
      database.saveProject(
        id: identity.projectId,
        name: existingProject.name,
        vcs: identity.vcs,
        remote: identity.remote,
      );
    }

    final WorktreeRecord? existing = database.worktreeAt(identity.worktreePath);
    final String dirName =
        existing?.dirName ??
        _allocateDirName(identity.name, identity.worktreeId);
    database.saveWorktree(
      id: identity.worktreeId,
      projectId: identity.projectId,
      path: identity.worktreePath,
      name: identity.name,
      dirName: dirName,
    );

    final String dataDir = _absoluteOverride(dataDirOverride, launchDir) ??
        '$workspacesDir${Platform.pathSeparator}$dirName';
    Directory(dataDir).createSync(recursive: true);
    if (!Platform.isWindows) {
      Process.runSync('chmod', <String>['700', dataDir]);
    }
    return WorkspaceInfo(
      projectId: identity.projectId,
      projectName: projectName,
      worktreeId: identity.worktreeId,
      worktreePath: identity.worktreePath,
      dataDir: dataDir,
    );
  }

  /// 重命名项目；只改数据库显示名。
  void rename(String projectId, String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('项目名不能为空');
    }
    if (trimmed.runes.length > 80) {
      throw ArgumentError('项目名不能超过 80 个字符');
    }
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(trimmed)) {
      throw ArgumentError('项目名不能包含控制字符');
    }
    database.renameProject(projectId, trimmed);
  }

  void close() => database.close();

  String? _absoluteOverride(String? override, String launchDir) {
    if (override == null || override.trim().isEmpty) return null;
    final String value = override.trim();
    if (value.startsWith('/') || RegExp(r'^[A-Za-z]:[/\\]').hasMatch(value)) {
      return value;
    }
    return '$launchDir${Platform.pathSeparator}$value';
  }

  String _canonical(String path) {
    try {
      return Directory(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return Directory(path).absolute.path;
    }
  }

  String _allocateDirName(String basename, String worktreeId) {
    for (final int length in <int>[12, 16, 20, 40]) {
      final String candidate = workspaceDirName(
        basename,
        worktreeId,
        hashLength: length,
      );
      if (database.worktreeByDirName(candidate) == null) {
        return candidate;
      }
    }
    throw StateError('无法分配工作区目录名：$basename');
  }
}

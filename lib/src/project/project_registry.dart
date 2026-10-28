/// 项目注册表：把项目身份落到 SQLite，并分配独立工作区目录。
library;

import 'dart:convert';
import 'dart:io';

import '../config/config_atomic_write.dart';
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
    final String? override = _absoluteOverride(dataDirOverride, launchDir);
    if (override != null && readOnlyWritePath(override)) {
      throw StateError(kReadOnlyPathMessage);
    }
    final ({String projectName, String dirName}) registration =
        _registerWithRetry(identity);
    final String dataDir =
        override ??
        '$workspacesDir${Platform.pathSeparator}${registration.dirName}';
    if (readOnlyWritePath(dataDir)) {
      throw StateError(kReadOnlyPathMessage);
    }
    Directory(dataDir).createSync(recursive: true);
    if (!Platform.isWindows) {
      Process.runSync('chmod', <String>['700', dataDir]);
    }
    final WorkspaceInfo info = WorkspaceInfo(
      projectId: identity.projectId,
      projectName: registration.projectName,
      worktreeId: identity.worktreeId,
      worktreePath: identity.worktreePath,
      dataDir: dataDir,
    );
    writeWorkspaceSidecar(info);
    return info;
  }

  ({String projectName, String dirName}) _registerWithRetry(
    ProjectIdentity identity,
  ) {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        return database.transaction(() => _register(identity));
      } on StateError catch (error) {
        if (attempt == 0 &&
            error.message.contains('UNIQUE constraint failed')) {
          continue;
        }
        rethrow;
      }
    }
    throw StateError('项目注册表写入冲突，请重试');
  }

  ({String projectName, String dirName}) _register(ProjectIdentity identity) {
    final ProjectRecord? existingProject = database.project(identity.projectId);
    final String projectName = existingProject?.name ?? identity.name;
    database.saveProject(
      id: identity.projectId,
      name: projectName,
      vcs: identity.vcs,
      remote: identity.remote,
    );
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
    return (projectName: projectName, dirName: dirName);
  }

  /// 已登记的全部 worktree，按最近使用排序。
  List<WorkspaceInfo> list() {
    return <WorkspaceInfo>[
      for (final WorktreeRecord worktree in database.worktrees())
        WorkspaceInfo(
          projectId: worktree.projectId,
          projectName:
              database.project(worktree.projectId)?.name ?? worktree.name,
          worktreeId: worktree.id,
          worktreePath: worktree.path,
          dataDir:
              '$workspacesDir${Platform.pathSeparator}${worktree.dirName}',
        ),
    ];
  }

  /// 重命名项目；只改数据库显示名，并尽量同步已有 sidecar。
  void rename(String projectId, String name, {String? dataDir}) {
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
    final Set<String> dirs = <String>{
      if (dataDir != null) dataDir,
      for (final WorktreeRecord worktree in database.worktrees())
        if (worktree.projectId == projectId)
          '$workspacesDir${Platform.pathSeparator}${worktree.dirName}',
    };
    for (final String dir in dirs) {
      final File sidecar = File('$dir${Platform.pathSeparator}$kWorkspaceSidecar');
      if (!sidecar.existsSync()) continue;
      final WorkspaceInfo? old = readWorkspaceSidecar(dir);
      if (old == null) continue;
      writeWorkspaceSidecar(
        WorkspaceInfo(
          projectId: old.projectId,
          projectName: trimmed,
          worktreeId: old.worktreeId,
          worktreePath: old.worktreePath,
          dataDir: old.dataDir,
        ),
      );
    }
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


/// 工作区 sidecar 文件名。
const String kWorkspaceSidecar = 'workspace.json';

/// 写入 `<dataDir>/workspace.json`（0600）；DB 丢失时 repair 靠它恢复。
void writeWorkspaceSidecar(WorkspaceInfo info) {
  final Map<String, Object?> data = <String, Object?>{
    'version': 1,
    'projectId': info.projectId,
    'projectName': info.projectName,
    'worktreeId': info.worktreeId,
    'worktreePath': info.worktreePath,
    'dirName': info.dataDir.split(Platform.pathSeparator).last,
  };
  writeFileAtomic(
    '${info.dataDir}${Platform.pathSeparator}$kWorkspaceSidecar',
    jsonEncode(data),
  );
}

/// 读取 `<dataDir>/workspace.json`；缺失或损坏返回 null。
WorkspaceInfo? readWorkspaceSidecar(String dataDir) {
  final File file = File('$dataDir${Platform.pathSeparator}$kWorkspaceSidecar');
  if (!file.existsSync()) return null;
  try {
    final Object? decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      return null;
    }
    final String? projectId = decoded['projectId'] as String?;
    final String? projectName = decoded['projectName'] as String?;
    final String? worktreeId = decoded['worktreeId'] as String?;
    final String? worktreePath = decoded['worktreePath'] as String?;
    if (projectId == null ||
        projectName == null ||
        worktreeId == null ||
        worktreePath == null) {
      return null;
    }
    return WorkspaceInfo(
      projectId: projectId,
      projectName: projectName,
      worktreeId: worktreeId,
      worktreePath: worktreePath,
      dataDir: dataDir,
    );
  } on FormatException {
    return null;
  }
}

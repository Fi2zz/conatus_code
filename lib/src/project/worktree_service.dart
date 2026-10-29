/// nava 自管的 git worktree：创建、列出、删除。
library;

import 'dart:io';

import 'project_paths.dart';
import 'project_registry.dart';

/// 一次创建结果。
class WorktreeCreateResult {
  const WorktreeCreateResult({
    required this.info,
    required this.branch,
    required this.path,
  });

  final WorkspaceInfo info;
  final String branch;
  final String path;
}

/// git worktree 管理器；只删除 strategy=git 且位于 nava worktrees 根下的条目。
class WorktreeService {
  WorktreeService({
    required this.registry,
    required this.workdir,
    String? worktreesDir,
  }) : worktreesDir = worktreesDir ?? _defaultRoot(registry);

  final ProjectRegistry registry;
  final String workdir;
  final String worktreesDir;

  List<WorkspaceInfo> list() => registry.list();

  /// 创建 worktree；branch 缺省为规范化后的名字。
  Future<WorktreeCreateResult> create(String name, {String? branch}) async {
    final String slug = workspaceSlug(name.trim());
    if (slug.isEmpty) throw ArgumentError('worktree 名字不能为空');
    final WorkspaceInfo source = registry.resolve(workdir);
    final String path =
        '$worktreesDir${Platform.pathSeparator}${source.projectShortId}'
        '${Platform.pathSeparator}$slug';
    if (Directory(path).existsSync()) {
      throw StateError('worktree 目录已存在：$path');
    }
    final String resolvedBranch = (branch?.trim().isNotEmpty ?? false)
        ? branch!.trim()
        : slug;
    final bool existingBranch =
        (branch?.trim().isNotEmpty ?? false) &&
        await _branchExists(source.worktreePath, resolvedBranch);
    Directory(File(path).parent.path).createSync(recursive: true);
    final ProcessResult result = await Process.run('git', <String>[
      '-C',
      source.worktreePath,
      'worktree',
      'add',
      if (!existingBranch) ...<String>['-b', resolvedBranch],
      path,
      if (existingBranch) resolvedBranch,
    ]);
    if (result.exitCode != 0) {
      if (Directory(path).existsSync()) {
        Directory(path).deleteSync(recursive: true);
      }
      throw StateError(_message(result));
    }
    try {
      final WorkspaceInfo info = registry.resolve(path, strategy: 'git');
      return WorktreeCreateResult(
        info: info,
        branch: resolvedBranch,
        path: info.worktreePath,
      );
    } catch (error) {
      await Process.run('git', <String>[
        '-C',
        source.worktreePath,
        'worktree',
        'remove',
        '--force',
        path,
      ]);
      if (Directory(path).existsSync()) {
        Directory(path).deleteSync(recursive: true);
      }
      rethrow;
    }
  }

  /// 删除一个 nava 自管 worktree；不清除主工作区或外部 worktree。
  ///
  /// [purge] 必须显式为 true：删除会连带移除该 worktree 的数据目录，
  /// 不能让它变成一次误触。
  Future<void> remove(String selector, {bool purge = false}) async {
    if (!purge) {
      throw StateError('删除 worktree 需要 --purge 确认（会删除数据目录）');
    }
    final WorkspaceInfo source = registry.resolve(workdir);
    final WorkspaceInfo? target = _find(selector);
    if (target == null) throw StateError('找不到 worktree：$selector');
    if (target.strategy != 'git') {
      throw StateError('只删除 nava 创建的 worktree：${target.worktreePath}');
    }
    final String root = _canonical(worktreesDir);
    if (!target.worktreePath.startsWith('$root${Platform.pathSeparator}')) {
      throw StateError('worktree 不在 nava 管理目录下：${target.worktreePath}');
    }
    final ProcessResult result = await Process.run('git', <String>[
      '-C',
      source.worktreePath,
      'worktree',
      'remove',
      target.worktreePath,
    ]);
    if (result.exitCode != 0) throw StateError(_message(result));
    registry.database.deleteWorktree(target.worktreeId);
    final Directory data = Directory(target.dataDir);
    if (data.existsSync()) data.deleteSync(recursive: true);
  }

  WorkspaceInfo? _find(String selector) {
    for (final WorkspaceInfo item in list()) {
      final String name = item.worktreePath.split(Platform.pathSeparator).last;
      if (name == selector ||
          item.worktreePath == selector ||
          item.worktreeId == selector ||
          item.worktreeId.startsWith(selector)) {
        return item;
      }
    }
    return null;
  }

  Future<bool> _branchExists(String repo, String branch) async {
    final ProcessResult result = await Process.run('git', <String>[
      '-C',
      repo,
      'show-ref',
      '--verify',
      '--quiet',
      'refs/heads/$branch',
    ]);
    return result.exitCode == 0;
  }

  String _message(ProcessResult result) {
    final String err = '${result.stderr}'.trim();
    return err.isEmpty ? 'git worktree 失败（${result.exitCode}）' : err;
  }

  String _canonical(String path) {
    try {
      return Directory(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return Directory(path).absolute.path;
    }
  }

  static String _defaultRoot(ProjectRegistry registry) {
    return '${File(registry.workspacesDir).parent.path}'
        '${Platform.pathSeparator}worktrees';
  }
}

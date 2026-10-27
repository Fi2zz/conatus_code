/// 项目身份：从 git remote / root commit / 规范路径推导稳定 ID。
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

/// 一个工作区的身份；同一 git remote 的 clone 共享 [projectId]。
class ProjectIdentity {
  const ProjectIdentity({
    required this.projectId,
    required this.worktreeId,
    required this.worktreePath,
    required this.name,
    this.vcs,
    this.remote,
  });

  /// 40 位小写十六进制。
  final String projectId;

  /// 40 位小写十六进制；按 worktree 路径区分。
  final String worktreeId;

  /// git 顶层目录，或非 git 目录的规范路径。
  final String worktreePath;

  /// [worktreePath] 的 basename。
  final String name;

  /// `git` 或 null。
  final String? vcs;

  /// 规范化后的 git remote，例如 `github.com/acme/lifts`。
  final String? remote;
}

/// 解析 [workdir] 的项目身份；非 git 目录绝不抛异常。
ProjectIdentity resolveProjectIdentity(String workdir) {
  final String canonical = _canonical(workdir);
  final String? root = _gitValue(canonical, <String>[
    'rev-parse',
    '--show-toplevel',
  ]);
  final String worktreePath = root == null || root.isEmpty
      ? canonical
      : _canonical(root);
  final String? rawRemote = root == null
      ? null
      : _gitValue(worktreePath, <String>[
          'config',
          '--get',
          'remote.origin.url',
        ]);
  final String? remote = rawRemote == null ? null : normalizeRemote(rawRemote);
  final String? rootCommit = root == null
      ? null
      : _gitValue(worktreePath, <String>[
          'rev-list',
          '--max-parents=0',
          'HEAD',
        ]);
  final String projectId = remote != null
      ? _hash('git-remote:$remote')
      : rootCommit != null && rootCommit.isNotEmpty
      ? _hash('git-root:${rootCommit.split('\n').first}')
      : _hash('directory:$canonical');
  return ProjectIdentity(
    projectId: projectId,
    worktreeId: _hash('worktree:$worktreePath'),
    worktreePath: worktreePath,
    name: _basename(worktreePath),
    vcs: root == null ? null : 'git',
    remote: remote,
  );
}

/// 把 `https://host/path.git` / `ssh://git@host/path` / `git@host:path`
/// 归一成 `host/path`；本地路径或 file: 返回 null。
String? normalizeRemote(String raw) {
  final String value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  String? host;
  String? path;
  final Match? scp = RegExp(r'^([^@/:]+@)?([^/:]+):(.+)$').firstMatch(value);
  if (scp != null &&
      !value.contains('://') &&
      !RegExp(r'^[A-Za-z]:[/\\]').hasMatch(value)) {
    host = scp.group(2);
    path = scp.group(3);
  } else {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    host = uri.host;
    path = uri.path;
  }
  final String cleanPath = (path ?? '')
      .replaceFirst(RegExp(r'^/+'), '')
      .replaceFirst(RegExp(r'\.git/?$'), '')
      .replaceFirst(RegExp(r'/+$'), '');
  if (host == null || host.isEmpty || cleanPath.isEmpty) {
    return null;
  }
  return '${host.toLowerCase()}/$cleanPath';
}

String _hash(String input) => sha1.convert(input.codeUnits).toString();

String _canonical(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return Directory(path).absolute.path;
  }
}

String _basename(String path) {
  final List<String> parts = Directory(path).uri.pathSegments;
  for (int index = parts.length - 1; index >= 0; index--) {
    if (parts[index].isNotEmpty) {
      return parts[index];
    }
  }
  return path;
}

String? _gitValue(String directory, List<String> args) {
  try {
    final ProcessResult result = Process.runSync('git', <String>[
      '-C',
      directory,
      ...args,
    ]);
    if (result.exitCode != 0) {
      return null;
    }
    final String value = (result.stdout as String).trim();
    return value.isEmpty ? null : value;
  } on ProcessException {
    return null;
  }
}

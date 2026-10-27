/// 工作区目录命名：可读 slug + worktree 短哈希。
library;

import 'dart:io';

import '../config/config_path.dart';

/// 把 basename 折成文件系统友好的 slug；保留 Unicode 字母/数字与 `._-`。
String workspaceSlug(String basename) {
  String slug = basename
      .replaceAll(RegExp(r'[^\p{L}\p{N}._-]+', unicode: true), '-')
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty || slug == '.' || slug == '..') {
    slug = 'workspace';
  }
  final Iterable<int> runes = slug.runes;
  if (runes.length <= 32) {
    return slug;
  }
  return String.fromCharCodes(runes.take(32));
}

/// `workspaces/<slug>-<worktreeId 前缀>`。
String workspaceDirName(
  String basename,
  String worktreeId, {
  int hashLength = 12,
}) {
  final int length = hashLength.clamp(1, worktreeId.length);
  return '${workspaceSlug(basename)}-${worktreeId.substring(0, length)}';
}

/// `$NAVA_HOME/workspaces`。
String workspacesRoot({Map<String, String>? env}) {
  return '${resolveConfigDir(env: env)}${Platform.pathSeparator}workspaces';
}

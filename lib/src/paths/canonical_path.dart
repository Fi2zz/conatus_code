/// 工具路径解析：家目录展开、canonical 化与 best-effort 回退。
///
/// 安全护栏（读台账 / 敏感文件）与指令层共用同一套路径身份，避免同一文件
/// 因相对/绝对/符号链接拼写不同而被当成两个目标。
library;

import 'dart:io';

/// `~/x` 展开；没有家目录时返回空串（调用方跳过该条）。
String expandToolHome(String value, String? home) {
  if (value != '~' && !value.startsWith('~${Platform.pathSeparator}')) {
    return value;
  }
  if (home == null || home.isEmpty) return '';
  if (value == '~') return home;
  return '$home${value.substring(1)}';
}

/// 尽力解析 canonical 路径：自身不存在时解析最近的已存在祖先，再拼回剩余部分。
///
/// 工具常读「尚不存在的路径」或只读目录里的单个文件；不这样做，未解析的
/// `/var/...` 与 canonical 的 `/private/var/...` 会让越界判定误伤合法路径。
String canonicalizeBestEffortPath(String path) {
  final String normalized = _normalizeLexical(path);
  final String sep = Platform.pathSeparator;
  final List<String> parts = normalized.split(sep);
  String suffix = '';
  while (parts.length > 1) {
    final String candidate = parts.join(sep);
    try {
      final String base = Directory(candidate).resolveSymbolicLinksSync();
      return '$base$suffix';
    } on FileSystemException {
      suffix = '$sep${parts.removeLast()}$suffix';
    }
  }
  return normalized;
}

/// 把工具传入的路径解析为 canonical 绝对路径；相对路径以 [workdir] 为基准。
///
/// 路径不存在时退回拼接后的绝对路径（后续读取自然失败），符号链接按真实
/// 目标返回，供调用方做越界判定与台账键。
String? canonicalToolPath(String workdir, String? home, String rawPath) {
  final String trimmed = rawPath.trim();
  if (trimmed.isEmpty) return null;
  final String expanded = expandToolHome(trimmed, home);
  if (expanded.isEmpty) return null;
  final File probe = File(expanded);
  final String absolute = _normalizeLexical(
    probe.isAbsolute ? expanded : '$workdir${Platform.pathSeparator}$expanded',
  );
  try {
    return FileSystemEntity.typeSync(absolute) == FileSystemEntityType.directory
        ? Directory(absolute).resolveSymbolicLinksSync()
        : File(absolute).resolveSymbolicLinksSync();
  } on FileSystemException {
    return canonicalizeBestEffortPath(absolute);
  }
}

/// 词法归一化：去掉空段与 `.`，折叠 `..`（不触盘）。
///
/// `resolveSymbolicLinks` 只对**存在**的路径有效；`nope/../a.txt` 这类
/// 「中间目录不存在」的写法会保留 `..`，导致台账键与 fs 层不一致。
String _normalizeLexical(String path) {
  final String sep = Platform.pathSeparator;
  final bool unc = path.startsWith('$sep$sep');
  final bool absolute = path.startsWith(sep);
  final List<String> parts = <String>[];
  for (final String part in path.split(sep)) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty && parts.last != '..') {
        parts.removeLast();
      } else if (!absolute) {
        parts.add('..');
      }
      continue;
    }
    parts.add(part);
  }
  final String joined = parts.join(sep);
  if (unc) return '$sep$sep$joined';
  return absolute ? '$sep$joined' : joined;
}

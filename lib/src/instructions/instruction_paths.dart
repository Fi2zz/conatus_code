/// 指令层用到的路径工具：家目录展开、路径拼接、包含判定与 canonical 解析。
library;

import 'dart:io';

/// `~/x` 展开；没有家目录时返回空串（调用方跳过该条）。
String expandInstructionHome(String value, String? home) {
  if (value != '~' && !value.startsWith('~${Platform.pathSeparator}')) {
    return value;
  }
  if (home == null || home.isEmpty) return '';
  if (value == '~') return home;
  return '$home${value.substring(1)}';
}

/// [child] 是否等于 [root] 或位于其下。
bool isWithinWorkdir(String child, String root) {
  if (child == root) return true;
  final String prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  return child.startsWith(prefix);
}

/// 拼接绝对路径（[relative] 不以分隔符开头）。
String joinInstructionPath(String root, String relative) =>
    '$root${Platform.pathSeparator}$relative';

/// 用户目录；环境变量缺失返回 `null`。
String? defaultInstructionHome() {
  final Map<String, String> env = Platform.environment;
  final String? raw = env['HOME'] ?? env['USERPROFILE'];
  final String? trimmed = raw?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// canonical 目录路径；不存在或解析失败时尽力解析最近的已存在祖先。
String canonicalDir(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return canonicalizeBestEffort(path);
  }
}

/// 尽力解析 canonical 路径：自身不存在时解析最近的已存在祖先，再拼回剩余部分。
///
/// 工具常读「尚不存在的路径」或只读目录里的单个文件；不这样做，未解析的
/// `/var/...` 与 canonical 的 `/private/var/...` 会让越界判定误伤合法路径。
String canonicalizeBestEffort(String path) {
  final String sep = Platform.pathSeparator;
  final List<String> parts = path.split(sep);
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
  return path;
}

/// 父目录；根目录返回自身。
String parentDir(String path) {
  final String trimmed =
      path.length > 1 && path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
  final int index = trimmed.lastIndexOf(Platform.pathSeparator);
  if (index < 0) return trimmed;
  if (index == 0) return Platform.pathSeparator;
  return trimmed.substring(0, index);
}

/// 项目根：最近的含 `.git` 的祖先；没有 git 时退回家目录（workdir 在其内）
/// 或工作目录本身。
///
/// 上限用家目录而不是文件系统根：从 `/tmp/x` 一路向上会把整台机器的
/// `AGENTS.md` 都读进系统提示，既不相关也不安全。
String findProjectRoot(String workdir, String? home) {
  String dir = workdir;
  while (true) {
    final String gitPath = joinInstructionPath(dir, '.git');
    if (Directory(gitPath).existsSync() || File(gitPath).existsSync()) {
      return dir;
    }
    final String parent = parentDir(dir);
    if (parent == dir) break;
    dir = parent;
  }
  if (home != null && isWithinWorkdir(workdir, home)) return home;
  return workdir;
}

/// 从 [root] 到 [workdir] 的目录链（由远及近）；workdir 不在 root 下时只含
/// workdir。
List<String> projectChain(String root, String workdir) {
  final List<String> chain = <String>[];
  String dir = workdir;
  while (true) {
    chain.add(dir);
    if (dir == root) return chain.reversed.toList(growable: false);
    final String parent = parentDir(dir);
    if (parent == dir) return <String>[workdir];
    dir = parent;
  }
}

/// 把工具传入的路径解析为 canonical 绝对路径；相对路径以 [workdir] 为基准。
///
/// 路径不存在时退回拼接后的绝对路径（后续读取自然失败），符号链接按真实
/// 目标返回，供调用方做越界判定。
String? resolveInstructionTargetPath(
  String workdir,
  String? home,
  String rawPath,
) {
  final String trimmed = rawPath.trim();
  if (trimmed.isEmpty) return null;
  final String expanded = expandInstructionHome(trimmed, home);
  if (expanded.isEmpty) return null;
  final File probe = File(expanded);
  final String absolute = probe.isAbsolute
      ? expanded
      : joinInstructionPath(workdir, expanded);
  try {
    return FileSystemEntity.typeSync(absolute) == FileSystemEntityType.directory
        ? Directory(absolute).resolveSymbolicLinksSync()
        : File(absolute).resolveSymbolicLinksSync();
  } on FileSystemException {
    return canonicalizeBestEffort(absolute);
  }
}

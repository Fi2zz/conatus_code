/// formatter 路径判定：工作区边界、`.opencode` 跳过与扩展名提取。
///
/// 所有路径在进入探针前都归一化为绝对路径；越界与受保护目录直接返回
/// `null`，调用方据此静默跳过，不把用户 OpenCode 的数据带进格式化命令。
library;

import 'dart:io';

/// 把 [path] 解析为工作区内的绝对路径；越界或位于 `.opencode` 返回 `null`。
String? resolveFormatterTarget(String workdir, String path) {
  final String raw = path.trim();
  if (raw.isEmpty) return null;
  final String root = _rootOf(workdir);
  final String lexical = _normalize(
    File(raw).isAbsolute ? raw : '$root${Platform.pathSeparator}$raw',
  );
  final String candidate = _resolveFile(lexical);
  if (candidate == root) return null;
  final String prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  if (!candidate.startsWith(prefix)) return null;
  final String relative = candidate.substring(prefix.length);
  if (relative.split(RegExp(r'[/\\]')).contains('.opencode')) return null;
  return candidate;
}

/// 文件扩展名（含点、小写）；无扩展名返回空串。
String formatterExtension(String path) {
  final String name = path.split(RegExp(r'[/\\]')).last;
  final int dot = name.lastIndexOf('.');
  if (dot <= 0) return '';
  return name.substring(dot).toLowerCase();
}

String _normalize(String path) => Uri.file(path).normalizePath().toFilePath();

/// 工作区根的规范拼写：解析符号链接，与沙箱根（fs jail / Seatbelt）一致。
///
/// 格式化命令把绝对路径写进命令行，路径字面量要与沙箱根同一拼写，否则
/// 命令策略会把合法路径判成越界。解析失败（目录不存在等）退回字面绝对路径。
String _rootOf(String workdir) {
  final Directory dir = Directory(workdir);
  try {
    return _normalize(dir.resolveSymbolicLinksSync());
  } on FileSystemException {
    return _normalize(dir.absolute.path);
  }
}

/// 文件存在时解析其符号链接；不存在则保留词法路径（后续会按已删除跳过）。
String _resolveFile(String path) {
  try {
    return _normalize(File(path).resolveSymbolicLinksSync());
  } on FileSystemException {
    return path;
  }
}

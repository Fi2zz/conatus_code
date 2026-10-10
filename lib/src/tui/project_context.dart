/// 项目上下文文件（`AGENTS.md` / `NAVA.md`）的读取与拼接。
///
/// v1 只读工作目录**根**的两个文件（不做向上递归）。读取前对文件与工作区根
/// 各取 canonical 路径并校验包含关系：**符号链接指向工作区外时一律不读**。
/// 为什么必须校验：克隆一个不可信仓库，里面放一个
/// `AGENTS.md -> ~/.nava/config.toml`（或 `-> ~/.ssh/id_rsa`）的符号链接，
/// `File.readAsString` 会跟随它把外部文件内容拼进 system prompt，随首轮请求
/// 发给远端模型——`dart:io` 直读不过 fs jail，符号链接就是越过 jail 的那道门。
library;

import 'dart:io';

/// 单个上下文文件的最大字符数；超限截断并标注。
const int kProjectContextMaxChars = 16384;

/// 读 `<workdir>/AGENTS.md` 与 `<workdir>/NAVA.md` 拼成一段项目上下文；
/// 两文件都不存在（或都读不出内容）返回 `null`。
///
/// 顺序：AGENTS.md 在前、NAVA.md 在后，中间空行分隔；每个文件超
/// [kProjectContextMaxChars] 截断并附标注。文件读取失败按空处理；工作区根
/// 无法解析（如目录不存在）时也按「无上下文」返回 `null`。
Future<String?> loadProjectContext(String workdir) async {
  final String? root = _canonicalRoot(workdir);
  if (root == null) return null;
  final String sep = Platform.pathSeparator;
  final String agents = await _readTrimmed('$workdir${sep}AGENTS.md', root);
  final String nava = await _readTrimmed('$workdir${sep}NAVA.md', root);
  if (agents.isEmpty && nava.isEmpty) return null;
  final StringBuffer buffer = StringBuffer();
  if (agents.isNotEmpty) {
    buffer.write(agents);
  }
  if (nava.isNotEmpty) {
    if (agents.isNotEmpty) buffer.write('\n\n');
    buffer.write(nava);
  }
  return buffer.toString();
}

/// 工作区根的 canonical 路径；不存在 / 无法解析时返回 `null`。
String? _canonicalRoot(String workdir) {
  try {
    return Directory(workdir).resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
}

/// 读文件并做大小截断；不存在、读取失败、或 canonical 路径落在
/// [canonicalRoot] 之外（符号链接越界）都返回空串。
Future<String> _readTrimmed(String path, String canonicalRoot) async {
  final File file = File(path);
  if (!file.existsSync()) return '';
  final String canonical;
  try {
    canonical = file.resolveSymbolicLinksSync();
  } on FileSystemException {
    return '';
  }
  final bool inside =
      canonical == canonicalRoot ||
      canonical.startsWith('$canonicalRoot${Platform.pathSeparator}');
  if (!inside) return '';
  String content;
  try {
    content = await file.readAsString();
  } on FileSystemException {
    return '';
  }
  if (content.length <= kProjectContextMaxChars) {
    return content;
  }
  return '${content.substring(0, kProjectContextMaxChars)}\n\n（已截断，原文超长）';
}

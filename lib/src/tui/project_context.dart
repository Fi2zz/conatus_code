/// 项目上下文文件（`AGENTS.md` / `NAVA.md`）的读取与拼接。
///
/// v1 只读工作目录**根**的两个文件：向上递归查找会越出 Layer 1 fs jail 的
/// 沙箱根被拒，且跨目录读取语义复杂；根目录文件已覆盖绝大多数项目。
library;

import 'dart:io';

/// 单个上下文文件的最大字符数；超限截断并标注。
const int kProjectContextMaxChars = 16384;

/// 读 `<workdir>/AGENTS.md` 与 `<workdir>/NAVA.md` 拼成一段项目上下文；
/// 两文件都不存在（或都读不出内容）返回 `null`。
///
/// 顺序：AGENTS.md 在前、NAVA.md 在后，中间空行分隔；每个文件超
/// [kProjectContextMaxChars] 截断并附标注。文件读取失败按空处理。
Future<String?> loadProjectContext(String workdir) async {
  final String agents = await _readTrimmed('$workdir${Platform.pathSeparator}AGENTS.md');
  final String nava = await _readTrimmed('$workdir${Platform.pathSeparator}NAVA.md');
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

/// 读文件并做大小截断；不存在或读取失败返回空串。
Future<String> _readTrimmed(String path) async {
  final File file = File(path);
  if (!file.existsSync()) return '';
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

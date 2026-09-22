/// 统一格式 diff 的解析：`--- / +++` 头 + `@@ -a,b +c,d @@` hunk。
library;

import 'diff_types.dart';

final RegExp _hunkHeader =
    RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');

/// 解析统一格式 diff 文本，返回文件级变更。
///
/// 目标路径取 `+++ b/`（git 的"新文件"侧）；手写 patch 只有 `--- a/` 时用它。
/// 解析不出任何文件时返回空列表。
// REASON: 逐行状态机解析是既定实现，else-if 链即解析分支本身。
List<DiffFile> parseUnifiedDiff(String text) {
  final List<DiffFile> files = <DiffFile>[];
  DiffFile? file;
  DiffHunk? hunk;
  for (final String raw in text.split('\n')) {
    if (raw.startsWith('--- ')) {
      file = DiffFile(path: _filePath(raw, 'a/'), hunks: <DiffHunk>[]);
      files.add(file);
    } else if (raw.startsWith('+++ ')) {
      _replaceDevNull(files, _filePath(raw, 'b/'));
    } else if (raw.startsWith('@@ ')) {
      final RegExpMatch? match = _hunkHeader.firstMatch(raw);
      if (match == null || file == null) continue;
      hunk = DiffHunk(
        oldStart: int.parse(match.group(1)!),
        oldLines: int.parse(match.group(2) ?? '1'),
        newStart: int.parse(match.group(3)!),
        newLines: int.parse(match.group(4) ?? '1'),
        lines: <String>[],
      );
      file.hunks.add(hunk);
    } else if (hunk != null &&
        (raw.startsWith(' ') || raw.startsWith('-') || raw.startsWith('+'))) {
      hunk.lines.add(raw);
    }
  }
  return files;
}

/// `--- /dev/null` 表示新文件：用紧随其后的 `+++ b/path` 作为目标路径。
void _replaceDevNull(List<DiffFile> files, String newPath) {
  if (files.isEmpty) return;
  final DiffFile last = files.last;
  if (last.path != '/dev/null') return;
  files[files.length - 1] = DiffFile(path: newPath, hunks: last.hunks);
}

/// 取 `---` / `+++` 行的路径值，去掉 `a/` / `b/` 前缀。
String _filePath(String raw, String prefix) {
  final String value = raw.substring(4).trim();
  return value.startsWith(prefix) ? value.substring(prefix.length) : value;
}

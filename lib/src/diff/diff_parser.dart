/// 统一格式 diff 的解析与内存行差异（`/diff` 数据层）。
///
/// 解析容忍 git 的扩展头（`diff --git` / `new file mode` / `rename from` /
/// `Binary files … differ`）与 `\ No newline at end of file`；目标路径统一去掉
/// `a/` / `b/` 前缀。二进制（NUL 或 git 二进制标记）只留文件级结论。
library;

import '../read_only_paths.dart';
import 'diff_builder.dart';
import 'diff_model.dart';
import 'diff_types.dart';
import 'unified_diff.dart' as unified;

/// 解析统一格式 diff 文本，返回文件级变更（按出现顺序）。
///
/// 解析不出任何文件时返回空列表。
List<FileDiff> parseUnifiedDiff(String text) {
  final UnifiedDiffBuilder builder = UnifiedDiffBuilder();
  for (final String line in text.split('\n')) {
    builder.add(line);
  }
  return builder.finish();
}

/// 内存中两侧文本的行差异；内容相同返回空列表。
///
/// 任一侧行数超过 [maxLines] 或内容含 NUL 时只返回文件级结论（无 hunk）。
/// [before] 为 `null` 表示新增文件，[after] 为 `null` 表示删除文件。
List<FileDiff> diffLines(
  String path,
  String? before,
  String? after, {
  int maxLines = 5000,
}) {
  if (before == after) return const <FileDiff>[];
  final String status = _statusFor(before, after);
  final String oldText = before ?? '';
  final String newText = after ?? '';
  final FileDiff? degraded = _degraded(
    path,
    status,
    oldText,
    newText,
    maxLines,
  );
  if (degraded != null) return <FileDiff>[degraded];
  final String patch = unified.buildUnifiedDiff(
    oldText: oldText,
    newText: newText,
    path: path,
  );
  if (patch.isNotEmpty) {
    return <FileDiff>[
      for (final FileDiff diff in parseUnifiedDiff(patch))
        diff.copyWith(status: status),
    ];
  }
  // 空文件的新增 / 删除没有 hunk，但仍是一条文件级变化。
  return before == null || after == null
      ? <FileDiff>[_file(path, status, 0, 0)]
      : const <FileDiff>[];
}

String _statusFor(String? before, String? after) {
  if (before == null) return 'added';
  if (after == null) return 'deleted';
  return 'modified';
}

/// 二进制 / 超长文件只给文件级结论；正常大小返回 `null` 交给行级 diff。
FileDiff? _degraded(
  String path,
  String status,
  String oldText,
  String newText,
  int maxLines,
) {
  if (oldText.contains('\u0000') || newText.contains('\u0000')) {
    return _file(path, 'binary', 0, 0);
  }
  final int oldCount = unified.splitLines(oldText).length;
  final int newCount = unified.splitLines(newText).length;
  if (oldCount <= maxLines && newCount <= maxLines) return null;
  return _file(path, status, newCount, oldCount, truncated: true);
}

FileDiff _file(
  String path,
  String status,
  int additions,
  int deletions, {
  bool truncated = false,
}) => FileDiff(
  path: path,
  status: status,
  hunks: const <DiffHunk>[],
  additions: additions,
  deletions: deletions,
  truncated: truncated,
);

/// `.opencode` 只读目录不进 `/diff`（内容经屏展示同样是泄漏面）。
bool showsDiffPath(String path) {
  final List<String> segments = path.split(RegExp(r'[/\\]'));
  return segments.isEmpty || segments.first.toLowerCase() != kOpenCodeDirName;
}

/// 审批差异预览：按工具参数计算审批浮层要展示的差异。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'unified_diff.dart';

/// 预览长度上限（字符）。
const int kPreviewMaxChars = 8000;

/// 计算审批浮层要展示的差异；无法计算（fs 缺失、参数不全、文件读取失败）
/// 时返回 `null`，调用方回落到工具静态描述。
Future<String?> buildApprovalPreview(
  FileSystem? fs,
  String toolName,
  Map<String, Object?> args,
) async {
  if (toolName == 'apply_patch') return _previewPatch(args['patch']);
  if (toolName == 'write_file') return _previewWrite(fs, args);
  if (toolName == 'edit_file') return _previewEdit(fs, args);
  return null;
}

/// apply_patch：patch 参数非空则直接展示（截断）。
String? _previewPatch(Object? patch) {
  if (patch is! String || patch.isEmpty) return null;
  return _truncate(patch);
}

/// write_file：读旧内容（FsError 一律按不存在处理）后做整文件 diff。
Future<String?> _previewWrite(
  FileSystem? fs,
  Map<String, Object?> args,
) async {
  final Object? path = args['path'];
  final Object? content = args['content'];
  if (path is! String || content is! String) return null;
  final FileSystem? resolved = fs;
  if (resolved == null) return null;
  final String oldText = await _readTextOrEmpty(resolved, path);
  return _previewDiff(oldText, content, path);
}

/// edit_file：按与工具相同的替换语义得到替换后文本再 diff。
Future<String?> _previewEdit(
  FileSystem? fs,
  Map<String, Object?> args,
) async {
  final Object? path = args['path'];
  final Object? oldString = args['old_string'];
  final Object? newString = args['new_string'];
  if (path is! String || oldString is! String || newString is! String) {
    return null;
  }
  final Object? rawReplaceAll = args['replace_all'];
  final bool replaceAll = rawReplaceAll is bool && rawReplaceAll;
  final FileSystem? resolved = fs;
  if (resolved == null) return null;
  final String oldText = await _readTextOrEmpty(resolved, path);
  final String? next = _applyEdit(oldText, oldString, newString, replaceAll);
  if (next == null) return null;
  return _previewDiff(oldText, next, path);
}

/// 生成 diff 预览；无实际改动返回占位文案。
String? _previewDiff(String oldText, String newText, String path) {
  final String diff = buildUnifiedDiff(oldText: oldText, newText: newText, path: path);
  return diff.isEmpty ? '（无实际改动）' : _truncate(diff);
}

/// 与 EditFileTool 相同的字面替换语义；old_string 不存在或语义无法确定时
/// 返回 `null`（old_string 与 new_string 相同视为无意义编辑）。
String? _applyEdit(
  String text,
  String oldString,
  String newString,
  bool replaceAll,
) {
  if (oldString == newString) return null;
  final int matches = oldString.allMatches(text).length;
  if (matches == 0) return null;
  if (matches > 1 && !replaceAll) return null;
  return replaceAll
      ? text.replaceAll(oldString, newString)
      : text.replaceFirst(oldString, newString);
}

/// 超出 [kPreviewMaxChars] 时截断并追加省略提示。
String _truncate(String text) {
  if (text.length <= kPreviewMaxChars) return text;
  return '${text.substring(0, kPreviewMaxChars)}\n…（截断）';
}

/// 读取文本；任何 [FsError] 一律按文件不存在（空串）处理。
Future<String> _readTextOrEmpty(FileSystem fs, String path) async {
  try {
    final FsTarget target = await fs.resolve(path);
    return await fs.readText(target);
  } on FsError {
    return '';
  }
}

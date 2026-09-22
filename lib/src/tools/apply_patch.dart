import 'package:conatus_foundation/conatus_foundation.dart';

import '../diff/diff_parse.dart';
import '../diff/diff_types.dart';
import '../diff/unified_diff.dart';

/// 应用统一格式（unified）diff 补丁的工具。
///
/// 逐文件按 hunk 倒序应用：上下文行（' ' 与 '-' 前缀）必须与现有内容逐行
/// 相等，任一文件失败立即返回失败（已应用的其它文件不回滚，靠版本守卫兜底）。
class ApplyPatchTool extends Tool {
  const ApplyPatchTool({required FileSystem fs}) : _fs = fs;

  final FileSystem _fs;

  @override
  String get name => 'apply_patch';

  @override
  String get description => '应用统一格式（unified）diff 补丁到文件。';

  @override
  ToolRisk get riskLevel => ToolRisk.high;

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String patch = ctx.str('patch');
    final List<DiffFile> files = parseUnifiedDiff(patch);
    if (files.isEmpty) {
      return ToolResult.failure(
        '无法解析 patch',
        error: const ToolError('PATCH_INVALID', '无法解析 patch'),
      );
    }
    final List<String> applied = <String>[];
    try {
      for (final DiffFile file in files) {
        await _applyFile(file);
        applied.add(file.path);
      }
    } on FsError catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code.code, e.message));
    } on _PatchContextError catch (e) {
      return ToolResult.failure(e.message, error: ToolError('PATCH_CONTEXT', e.message));
    }
    return ToolResult.success(
      '已应用 ${applied.length} 个文件：${applied.join(', ')}',
      value: <String, Object?>{'files': applied, 'diff': patch},
    );
  }

  /// 应用单个文件的所有 hunk（倒序，避免行号漂移）；目标不存在视为空文件。
  Future<void> _applyFile(DiffFile file) async {
    final FsTarget target = await _fs.resolve(file.path);
    final String oldText = await _readTextOrEmpty(target);
    final List<String> lines = List<String>.of(splitLines(oldText));
    final bool trailingNewline = oldText.endsWith('\n');
    for (final DiffHunk hunk in file.hunks.reversed) {
      _applyHunk(lines, hunk, file.path);
    }
    final String next = '${lines.join('\n')}${trailingNewline ? '\n' : ''}';
    await _fs.writeText(target, next);
  }

  /// 应用一个 hunk：校验上下文行与现有内容逐行相等，替换为新侧内容。
  // REASON: diff 应用是既定算法实现，前缀分支即 hunk 行语义本身。
  void _applyHunk(List<String> lines, DiffHunk hunk, String path) {
    final int start = hunk.oldStart < 1 ? 0 : hunk.oldStart - 1;
    if (start > lines.length) {
      throw _PatchContextError('起始行越界：$path 第 ${hunk.oldStart} 行');
    }
    int pos = start;
    final List<String> replacement = <String>[];
    for (final String raw in hunk.lines) {
      final String prefix = raw.substring(0, 1);
      final String text = raw.substring(1);
      if (prefix == '+') {
        replacement.add(text);
      } else if (prefix == '-' || prefix == ' ') {
        if (pos >= lines.length || lines[pos] != text) {
          throw _PatchContextError('上下文不匹配：$path 第 ${pos + 1} 行');
        }
        pos++;
        if (prefix == ' ') replacement.add(text);
      }
    }
    lines.replaceRange(start, pos, replacement);
  }

  /// 读取旧内容；目标不存在视为空串，其它 [FsError] 上抛。
  Future<String> _readTextOrEmpty(FsTarget target) async {
    try {
      return await _fs.readText(target);
    } on FsError catch (e) {
      if (e.code == FsErrorCode.notFound) return '';
      rethrow;
    }
  }
}

/// 上下文行与现有内容不匹配。
class _PatchContextError implements Exception {
  const _PatchContextError(this.message);

  final String message;
}

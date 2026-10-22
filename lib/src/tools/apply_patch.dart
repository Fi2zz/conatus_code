import 'package:conatus_foundation/conatus_foundation.dart';

import '../diff/apply.dart';
import '../diff/diff_parse.dart';
import '../diff/diff_types.dart';

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
    } on PatchContextException catch (e) {
      return ToolResult.failure(e.message, error: ToolError('PATCH_CONTEXT', e.message));
    }
    return ToolResult.success(
      '已应用 ${applied.length} 个文件：${applied.join(', ')}',
      value: <String, Object?>{'files': applied, 'diff': patch},
    );
  }

  /// 应用单个文件（目标不存在视为空文件）；应用语义见 diff/apply.dart。
  Future<void> _applyFile(DiffFile file) async {
    final FsTarget target = await _fs.resolve(file.path);
    final String oldText = await _readTextOrEmpty(target);
    await _fs.writeText(target, applyDiffFile(oldText, file));
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

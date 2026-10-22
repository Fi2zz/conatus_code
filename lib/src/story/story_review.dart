/// 事前审阅门：交互模式下拦截写工具，把编辑登记为待定补丁而不落盘
/// （设计文档 §2.2：AI 产出 = pending scope，人接受才生效）。
///
/// 挂载顺序：中间件链最后注册者最外层先命中（见 ToolRegistry._chain 的
/// reversed 包裹），控制器在 `_syncPermissionMode` 里审批门之后重挂本门，
/// 保证写工具先被这里拦住、不再触发审批弹窗（pending 即审阅）。
/// headless 不经过控制器，天然不拦截（没有人审，文件必须真写）。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import '../diff/apply.dart';
import '../diff/diff_parse.dart';
import '../diff/diff_types.dart';
import 'story.dart';
import 'story_pending.dart';

/// 事前审阅门：把 `write_file` / `edit_file` / `apply_patch` 拦成待定补丁。
class StoryReviewGate {
  /// 以待定补丁列表 [pending] 与读文件内容的 [fs] 缝构造。
  StoryReviewGate({required this.pending, this.fs});

  /// 待定补丁入列目标。
  final StoryPending pending;

  /// 读当前内容的文件系统缝；缺失时全部 fail-open 放行。
  final FileSystem? fs;

  /// 挂到工具注册表（返回撤销函数）。
  Disposer mount(ToolRegistry tools) =>
      tools.use(intercept, tag: 'storyReview');

  /// 中间件：能算出「执行后内容」的写工具调用 → 登记 pending、不落盘。
  ///
  /// 算不出（edit 的 old 串找不到、patch 上下文不适用、参数不全）时
  /// fail-open 放行给 next()——拦一个注定失败的编辑只会把真实错误藏住，
  /// 让工具自己报错回到模型才是正确的反馈路径。
  Future<ToolResult> intercept(
    ToolCall call,
    Future<ToolResult> Function() next,
  ) async {
    if (!kStoryToolNames.contains(call.name)) return next();
    final List<PatchOp>? ops = await previewEditedOps(fs, call);
    if (ops == null) return next();
    final int n = await pending.feedOps(ops, source: call.name, fs: fs);
    return ToolResult.success(
      '编辑已登记为待定补丁 #$n（${ops.length} 个文件），待人审阅生效；'
      '无需重试，可继续其它工作。',
    );
  }
}

/// 算出写工具「若执行后的新内容」并组装 ops（块 id = 文件路径，op 带目标
/// 全文）；算不出返回 `null`（调用方 fail-open 放行）。
Future<List<PatchOp>?> previewEditedOps(FileSystem? fs, ToolCall call) async {
  final FileSystem? seam = fs;
  if (seam == null) return null;
  try {
    return await _opsFor(seam, call);
  } on FsError {
    return null;
  } on PatchContextException {
    return null;
  }
}

Future<List<PatchOp>?> _opsFor(FileSystem fs, ToolCall call) async {
  if (call.name == 'write_file') return _writeOps(fs, call.arguments);
  if (call.name == 'edit_file') return _editOps(fs, call.arguments);
  if (call.name == 'apply_patch') return _patchOps(fs, call.arguments);
  return null;
}

/// write_file：create 且文件已存在时真实工具会失败 → 放行；append 语义为
/// 旧内容 + 新内容；overwrite 为整文件替换。
Future<List<PatchOp>?> _writeOps(
  FileSystem fs,
  Map<String, Object?> args,
) async {
  final Object? path = args['path'];
  final Object? content = args['content'];
  if (path is! String || content is! String) return null;
  final String? old = await _readTextOrNull(fs, path);
  final String mode = args['mode'] is String
      ? args['mode'] as String
      : 'create';
  if (mode == 'create' && old != null) return null;
  final String next = mode == 'append' ? '${old ?? ''}$content' : content;
  return <PatchOp>[_fileOp(path, old, next)];
}

/// edit_file：与 EditFileTool 相同的字面替换语义（见 [applyEditText]）；
/// 文件不存在或替换语义不成立 → 放行。
Future<List<PatchOp>?> _editOps(
  FileSystem fs,
  Map<String, Object?> args,
) async {
  final Object? path = args['path'];
  final Object? oldString = args['old_string'];
  final Object? newString = args['new_string'];
  if (path is! String || oldString is! String || newString is! String) {
    return null;
  }
  final String? old = await _readTextOrNull(fs, path);
  if (old == null) return null;
  final String? next = applyEditText(
    old,
    oldString,
    newString,
    args['replace_all'] == true,
  );
  if (next == null) return null;
  return <PatchOp>[ReplaceBlockOp(blockId: path, text: next)];
}

/// apply_patch：解析后逐文件应用到当前内容（多文件 = 多个 op，同属一个
/// 待定补丁）；解析失败或上下文不适用 → 放行。
Future<List<PatchOp>?> _patchOps(
  FileSystem fs,
  Map<String, Object?> args,
) async {
  final Object? patch = args['patch'];
  if (patch is! String || patch.isEmpty) return null;
  final List<DiffFile> files = parseUnifiedDiff(patch);
  if (files.isEmpty) return null;
  final List<PatchOp> ops = <PatchOp>[];
  for (final DiffFile file in files) {
    final String? old = await _readTextOrNull(fs, file.path);
    ops.add(_fileOp(file.path, old, applyDiffFile(old ?? '', file)));
  }
  return ops;
}

PatchOp _fileOp(String path, String? old, String next) => old == null
    ? InsertBlockOp(blockId: path, text: next)
    : ReplaceBlockOp(blockId: path, text: next);

/// 读取当前内容；不存在返回 null，其它 [FsError] 上抛（由调用方 fail-open）。
Future<String?> _readTextOrNull(FileSystem fs, String path) async {
  try {
    return await fs.readText(await fs.resolve(path));
  } on FsError catch (e) {
    if (e.code == FsErrorCode.notFound) return null;
    rethrow;
  }
}

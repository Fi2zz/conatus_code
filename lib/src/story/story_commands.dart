/// `/story` 子命令的纯逻辑：preview 渲染与 discard 写回。
library;

import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'story_blocks.dart';

/// 预览 [state]（`/story preview <n>`）：段落块按文件重组后逐文件列出，
/// 每文件最多 [maxLines] 行。
String renderStoryPreview(DocumentState state, {int maxLines = 10}) {
  if (state.blocks.isEmpty) return '该时刻文档为空。';
  final Map<String, List<DocBlock>> grouped = <String, List<DocBlock>>{};
  for (final DocBlock block in state.blocks) {
    grouped.putIfAbsent(pathOfBlock(block.id), () => <DocBlock>[]).add(block);
  }
  final StringBuffer buffer = StringBuffer('该时刻文档（${grouped.length} 个文件）：');
  for (final MapEntry<String, List<DocBlock>> entry in grouped.entries) {
    final List<String> lines = renderFileText(entry.value).split('\n');
    buffer.write('\n── ${entry.key} ──\n');
    buffer.write(lines.take(maxLines).join('\n'));
    if (lines.length > maxLines) buffer.write('\n…（共 ${lines.length} 行）');
  }
  return buffer.toString();
}

/// 驳回一个补丁的结果。
class StoryDiscardResult {
  /// 以被驳回的 [patchId]、写回成功的文件 [written] 与 fold 后消失而保守
  /// 保留的文件 [kept] 构造。
  const StoryDiscardResult({
    required this.patchId,
    required this.written,
    required this.kept,
  });

  /// 被驳回的补丁 id。
  final String patchId;

  /// 已写回 fold 后内容的文件。
  final List<String> written;

  /// fold 后已不存在的文件（保守：不删盘上的文件）。
  final List<String> kept;
}

/// 驳回第 [index] 个补丁（1 起，按时间轴序号）：作废 → 重算 fold → 把该
/// 补丁触及的文件**写回** fold 后的内容（经 fs 缝）。AI 与人的补丁同路径
/// 处理；驳回本身是 `doc/void` 故事事件。
///
/// [fs] 为 null 时只作废不写回。序号越界抛 [ArgumentError]。
Future<StoryDiscardResult> discardStoryPatch(
  DocEngine engine,
  FileSystem? fs,
  int index,
) async {
  final List<DocPatch> patches = engine.log.patches;
  if (index < 1 || index > patches.length) {
    throw ArgumentError.value(index, 'index', '补丁序号越界（/story 查看时间轴）');
  }
  final DocPatch patch = patches[index - 1];
  // 块 id 是 `path#hash`（段落粒度）或旧形态整路径——统一映射回文件路径。
  final Set<String> touched = <String>{
    for (final PatchOp op in patch.ops) pathOfBlock(op.blockId),
  };
  await engine.discard(patch.id);
  return _writeBack(engine, fs, patch.id, touched);
}

/// 把 [touched] 的文件写回 fold 后内容；fold 后消失的记入 kept（不删文件）。
Future<StoryDiscardResult> _writeBack(
  DocEngine engine,
  FileSystem? fs,
  String patchId,
  Set<String> touched,
) async {
  final DocumentState state = engine.state;
  final List<String> written = <String>[];
  final List<String> kept = <String>[];
  for (final String path in touched) {
    final List<DocBlock> blocks = blocksOfFile(state, path);
    if (blocks.isEmpty) {
      kept.add(path);
      continue;
    }
    if (fs == null) continue;
    await fs.writeText(await fs.resolve(path), renderFileText(blocks));
    written.add(path);
  }
  return StoryDiscardResult(patchId: patchId, written: written, kept: kept);
}

/// 渲染驳回结果（controller 输出用）。
String renderStoryDiscard(StoryDiscardResult result) {
  final StringBuffer buffer = StringBuffer('已驳回补丁 ${result.patchId}。');
  if (result.written.isNotEmpty) {
    buffer.write('已写回：${result.written.join(', ')}。');
  }
  for (final String path in result.kept) {
    buffer.write('$path 在故事中已不存在，文件保留未删。');
  }
  return buffer.toString();
}

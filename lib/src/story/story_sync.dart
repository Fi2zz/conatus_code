/// 段落同步器：把「文件旧 fold 状态 → 新内容」对齐成段落级 op 序列
/// （设计文档 §3：块粒度从文件细到段落）。纯函数，不含 IO；块词汇
/// （切分 / id / 归属 / 重建）见 story_blocks.dart。
library;

import 'package:conatus_doc/conatus_doc.dart';

import 'story_blocks.dart';

/// 段落数上限：超过则整体退化为 `path#full` 单块（LCS 是 O(n·m)，且
/// 超长文件的段落级故事没有可读性）。
const int kParagraphLimit = 512;

/// 引擎状态驱动的入口：算出 [path] 文件从 fold 到 [newText] 的段落 ops。
List<PatchOp> syncFileOps({
  required DocumentState state,
  required String path,
  required String newText,
}) {
  final List<DocBlock> fileBlocks = blocksOfFile(state, path);
  final String? anchor = fileBlocks.isEmpty
      ? anchorForNewFile(state.blocks, path)
      : _anchorBeforeFirst(state.blocks, fileBlocks.first);
  return buildSyncOps(
    path: path,
    oldBlocks: fileBlocks,
    newText: newText,
    anchorBefore: anchor,
  );
}

/// 新文件首段的锚点：fold 里路径序小于 [path] 的最后一个块。
String? anchorForNewFile(List<DocBlock> blocks, String path) {
  String? anchor;
  for (final DocBlock b in blocks) {
    if (pathOfBlock(b.id).compareTo(path) < 0) anchor = b.id;
  }
  return anchor;
}

String? _anchorBeforeFirst(List<DocBlock> blocks, DocBlock first) {
  final int at = indexOfBlock(blocks, first.id);
  return at <= 0 ? null : blocks[at - 1].id;
}

/// 整块兜底（同步器异常时的 fail-safe）：语义与超段数退化一致
/// （`path#full` 单块）。
List<PatchOp> wholeFileOps({
  required DocumentState state,
  required String path,
  required String newText,
}) {
  final List<DocBlock> fileBlocks = blocksOfFile(state, path);
  final String? anchor = fileBlocks.isEmpty
      ? anchorForNewFile(state.blocks, path)
      : _anchorBeforeFirst(state.blocks, fileBlocks.first);
  return _fullBlockOps(path, fileBlocks, newText, anchor);
}

/// 对齐 [oldBlocks]（该文件 fold 块，保持顺序）与 [newText] 的段落序列：
/// 未匹配旧段 → RemoveBlockOp；未匹配新段 → InsertBlockOp（锚在前一个保留
/// 段之后；首段锚 [anchorBefore]，没有则文档开头）。修改 = remove + insert，
/// 不虚构成 replace。超 [kParagraphLimit] 退化为 `path#full` 单块。
List<PatchOp> buildSyncOps({
  required String path,
  required List<DocBlock> oldBlocks,
  required String newText,
  String? anchorBefore,
}) {
  final List<String> newParas = splitParagraphs(newText);
  if (oldBlocks.length > kParagraphLimit || newParas.length > kParagraphLimit) {
    return _fullBlockOps(path, oldBlocks, newText, anchorBefore);
  }
  final List<String> oldParas = oldBlocks.map((DocBlock b) => b.text).toList();
  final List<(int, int)> pairs = _lcsPairs(oldParas, newParas);
  return _buildOps(path, oldBlocks, newParas, pairs, anchorBefore);
}

/// 退化路径：折叠为单个 `path#full` 块。
List<PatchOp> _fullBlockOps(
  String path,
  List<DocBlock> oldBlocks,
  String newText,
  String? anchorBefore,
) {
  final String fullId = '$path#full';
  if (oldBlocks.length == 1 && oldBlocks.single.id == fullId) {
    return <PatchOp>[ReplaceBlockOp(blockId: fullId, text: newText)];
  }
  return <PatchOp>[
    for (final DocBlock b in oldBlocks) RemoveBlockOp(blockId: b.id),
    InsertBlockOp(blockId: fullId, text: newText, afterId: anchorBefore),
  ];
}

List<PatchOp> _buildOps(
  String path,
  List<DocBlock> oldBlocks,
  List<String> newParas,
  List<(int, int)> pairs,
  String? anchorBefore,
) {
  final Set<int> matchedOld = <int>{for (final (int i, _) in pairs) i};
  final Map<int, int> newToOld = <int, int>{
    for (final (int i, int j) in pairs) j: i,
  };
  final List<PatchOp> ops = <PatchOp>[
    for (int i = 0; i < oldBlocks.length; i++)
      if (!matchedOld.contains(i)) RemoveBlockOp(blockId: oldBlocks[i].id),
  ];
  final Set<String> taken = <String>{for (final DocBlock b in oldBlocks) b.id};
  String? anchor = anchorBefore;
  for (int j = 0; j < newParas.length; j++) {
    final int? kept = newToOld[j];
    if (kept != null) {
      anchor = oldBlocks[kept].id;
      continue;
    }
    final String id = _allocParagraphId(path, newParas[j], taken);
    ops.add(InsertBlockOp(blockId: id, text: newParas[j], afterId: anchor));
    anchor = id;
  }
  return ops;
}

/// 分配不冲突的段落块 id（重复段落加 `-2`/`-3` 后缀）。
String _allocParagraphId(String path, String para, Set<String> taken) {
  final String base = paragraphBlockId(path, para);
  if (taken.add(base)) return base;
  int suffix = 2;
  while (!taken.add('$base-$suffix')) {
    suffix++;
  }
  return '$base-$suffix';
}

/// 段落文本的 LCS 匹配对（保持双方顺序）。
// REASON: 标准 LCS 动态规划 + 回溯，属算法实现豁免（分支即 DP 转移本身）。
List<(int, int)> _lcsPairs(List<String> oldSeq, List<String> newSeq) {
  final int n = oldSeq.length;
  final int m = newSeq.length;
  final List<List<int>> dp = List<List<int>>.generate(
    n + 1,
    (_) => List<int>.filled(m + 1, 0),
  );
  for (int i = n - 1; i >= 0; i--) {
    for (int j = m - 1; j >= 0; j--) {
      dp[i][j] = oldSeq[i] == newSeq[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final List<(int, int)> pairs = <(int, int)>[];
  int i = 0;
  int j = 0;
  while (i < n && j < m) {
    if (oldSeq[i] == newSeq[j]) {
      pairs.add((i, j));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return pairs;
}

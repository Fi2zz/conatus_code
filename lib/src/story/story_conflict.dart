/// apply 冲突检测与双版本落盘（设计文档 §3 第二档：块级并发，冲突处留
/// 双版本）。pending 记着提出时的基底；apply 时磁盘 ≠ 基底即冲突——
/// 不覆盖、不静默失败，git 式 marker 合并文本落盘，人的版本在上。
library;

import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// 冲突块开围栏（人的版本在上）。
const String kConflictOpen = '<<<<<<< 你的版本（人的编辑）';

/// 冲突块分隔线。
const String kConflictSplit = '=======';

/// 冲突块闭围栏（AI 待定补丁在下）。
String conflictClose(int index) => '>>>>>>> AI 待定补丁 #$index';

/// git 式双版本合并文本：[current]（人的磁盘现状）在上，[incoming]（AI
/// 待定内容）在下。
String mergeConflictVersions({
  required String current,
  required String incoming,
  required int index,
}) {
  final String ours = current.endsWith('\n') ? current : '$current\n';
  final String theirs = incoming.endsWith('\n') ? incoming : '$incoming\n';
  return '$kConflictOpen\n$ours$kConflictSplit\n$theirs${conflictClose(index)}\n';
}

/// 应用单个待定 op：磁盘内容 == 基底 → 干净写入；不等 → 冲突，写双版本
/// 合并文本。返回实际落盘文本（落故事的段落 ops 由调用方按它生成——
/// 故事与磁盘一致）。[bases] 缺失该文件的记录时退化为直接写（旧数据兼容）。
Future<({String text, bool conflicted})> applyPendingOp(
  FileSystem fs,
  PatchOp op,
  Map<String, String?>? bases,
  int index,
) async {
  final String text = pendingOpText(op);
  final String? base = bases == null ? null : bases[op.blockId];
  final bool tracked = bases != null && bases.containsKey(op.blockId);
  final String? current = await _readOrNull(fs, op.blockId);
  final bool clean = !tracked || current == base;
  final String landed = clean
      ? text
      : mergeConflictVersions(
          current: current ?? '',
          incoming: text,
          index: index,
        );
  await fs.writeText(await fs.resolve(op.blockId), landed);
  return (text: landed, conflicted: !clean);
}

/// 待定 op 的目标全文（v1 只有 Insert / Replace 能进 apply 路径）。
String pendingOpText(PatchOp op) {
  if (op is InsertBlockOp) return op.text;
  if (op is ReplaceBlockOp) return op.text;
  return '';
}

/// 记录提出时的基底：每个目标文件的当前内容（null = 当时不存在）；
/// [fs] 缺失时返回空表（无基底记录，apply 退化为直接写）。
Future<Map<String, String?>> readPendingBases(
  FileSystem? fs,
  List<PatchOp> ops,
) async {
  final Map<String, String?> out = <String, String?>{};
  if (fs == null) return out;
  for (final PatchOp op in ops) {
    out[op.blockId] = await _readOrNull(fs, op.blockId);
  }
  return out;
}

Future<String?> _readOrNull(FileSystem fs, String path) async {
  try {
    return await fs.readText(await fs.resolve(path));
  } on FsError catch (e) {
    if (e.code == FsErrorCode.notFound) return null;
    rethrow;
  }
}

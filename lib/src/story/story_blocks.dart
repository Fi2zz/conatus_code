/// 段落块词汇：切分、块 id、归属判断与文件内容重建（纯函数）。
///
/// 块 id 形态：`<相对路径>#<内容 sha1 前 8 位>`，同文件内容重复的段落加
/// `-2`/`-3` 后缀去重；确定性、跨进程稳定。旧会话里的文件粒度块
/// （id = 路径，无 `#` 前缀）不迁移：id 不同即不同块，共存不冲突。
library;

import 'dart:convert';

import 'package:conatus_doc/conatus_doc.dart';
import 'package:crypto/crypto.dart';

/// 按空行（`\n\n+`，允许空行内含空白）切段；空文件返回空。
/// 与 [renderFileText] 的 `\n\n` 连接在 prose 常规形态下往返一致。
List<String> splitParagraphs(String text) {
  if (text.trim().isEmpty) return const <String>[];
  return <String>[
    for (final String part in text.split(RegExp(r'\n\s*\n')))
      part.replaceAll(RegExp(r'^\n+|\n+$'), ''),
  ];
}

/// 规范化：split + render 的往返形态（归因比较用，吸收多余空行差异）。
String normalizeParagraphText(String text) =>
    splitParagraphs(text).join('\n\n');

/// 块 id 的文件路径部分；无 `#` 前缀的旧格式整块返回自身（兼容）。
String pathOfBlock(String blockId) {
  final int at = blockId.indexOf('#');
  return at < 0 ? blockId : blockId.substring(0, at);
}

/// 块是否属于 [path] 文件（新形态 `$path#…` 或旧形态整块 `path`）。
bool blockBelongsTo(String blockId, String path) =>
    blockId == path || blockId.startsWith('$path#');

/// fold 里属于 [path] 的块（保持 fold 顺序）。
List<DocBlock> blocksOfFile(DocumentState state, String path) => <DocBlock>[
  for (final DocBlock b in state.blocks)
    if (blockBelongsTo(b.id, path)) b,
];

/// 文件内容重建：该文件的块按序以 `\n\n` 连接。
String renderFileText(List<DocBlock> blocks) =>
    blocks.map((DocBlock b) => b.text).join('\n\n');

/// op 携带的文本（Insert / Replace）；Remove / Move 返回 null。
String? opTextOf(PatchOp op) {
  if (op is InsertBlockOp) return op.text;
  if (op is ReplaceBlockOp) return op.text;
  return null;
}

/// 段落块 id：`$path#<sha1 前 8>`（去重后缀由调用方分配）。
String paragraphBlockId(String path, String paragraph) {
  final String hash = sha1
      .convert(utf8.encode(paragraph))
      .toString()
      .substring(0, 8);
  return '$path#$hash';
}

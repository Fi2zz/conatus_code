/// 故事层的渲染与路径提取（纯函数）。
library;

import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'story_blocks.dart';

/// 取出本次编辑涉及的文件：`write_file` / `edit_file` 在参数里，
/// `apply_patch`（多文件）在结果的 `files` 里（与 lint 同一取法）。
List<String> storyEditedPaths(ToolCall call, ToolResult result) {
  final Object? single = call.arguments['path'];
  if (single is String && single.isNotEmpty) return <String>[single];
  final Object? value = result.value;
  if (value is! Map<String, Object?>) return const <String>[];
  final Object? files = value['files'];
  if (files is! List) return const <String>[];
  return files.whereType<String>().where((String p) => p.isNotEmpty).toList();
}

/// 渲染补丁时间轴（`/story` 输出）：序号、作者、补丁 id、涉及文件、时间。
String renderStoryTimeline(List<DocPatch> patches) {
  if (patches.isEmpty) return '故事线：还没有补丁。';
  final StringBuffer buffer = StringBuffer('故事线（${patches.length} 个补丁）：');
  for (final (int index, DocPatch patch) in patches.indexed) {
    final String author = patch.author == PatchAuthor.ai ? 'AI' : '人';
    final String files = patch.ops.map(storyOpLabel).join('、');
    buffer.write(
      '\n  ${index + 1}. [$author] ${patch.id}'
      ' — ${files.isEmpty ? '（无文件）' : files}'
      '（${storyPatchTime(patch.id)}）',
    );
  }
  return buffer.toString();
}

/// 从补丁 id（`story-<微秒>-<序号>` / `human-<微秒>-<序号>`）解析落定时间；
/// 不可解析时返回 `-`。
String storyPatchTime(String id) {
  final List<String> parts = id.split('-');
  if (parts.length != 3) return '-';
  final int? micros = int.tryParse(parts[1]);
  if (micros == null) return '-';
  final String text = DateTime.fromMicrosecondsSinceEpoch(
    micros,
  ).toLocal().toString();
  return text.substring(0, 19);
}

/// 单个 op 的展示标签：路径 + 段落摘要（首 20 字）；删除段标注（删）。
/// 块 id 的 hash 部分不外露（它只是身份，不是内容）。
String storyOpLabel(PatchOp op) {
  final String path = pathOfBlock(op.blockId);
  final String? text = opTextOf(op);
  if (text == null) return '$path（删）';
  final String brief = text.trim().replaceAll('\n', ' ');
  if (brief.length <= 20) return '$path「$brief」';
  return '$path「${brief.substring(0, 20)}…」';
}

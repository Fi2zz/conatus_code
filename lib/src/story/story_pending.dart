/// 待应用补丁通道（第二通道）：模型在 ```` ```ops ```` 围栏块里**提议**修改，
/// 人审阅后 `/story apply <i>` 才生效。
///
/// pending 是临时态：不落 story-log，随会话子上下文释放。应用成功才走
/// 正常 `DocEngine.commit` 落 `doc/patch` 事件。
library;

import 'dart:async';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'story_conflict.dart';
import 'story_sync.dart';

/// 编译助手文本里的 ops 块；无块或编译失败（普通回复里自然出现的
/// ```` ``` ```` 块）都返回空——绝不因此炸会话。
List<PatchOp> tryCompileOps(String text) {
  try {
    return compileOpsBlock(text);
  } on FormatException {
    return const <PatchOp>[];
  } on ArgumentError {
    return const <PatchOp>[];
  }
}

/// 会话级的待应用补丁列表。两个来源：助手回复的 ops 块（[feed]）与
/// 事前审阅门拦下的写工具调用（[feedOps]，[source] 记工具名）。
class StoryPending {
  final List<DocPatch> _patches = <DocPatch>[];
  final Map<String, String> _sources = <String, String>{};

  /// 补丁 id →（文件 → 提出时的基底内容；null = 当时不存在）。
  final Map<String, Map<String, String?>> _bases =
      <String, Map<String, String?>>{};
  int _seq = 0;

  /// 待应用补丁（追加序）。
  List<DocPatch> get patches => List<DocPatch>.unmodifiable(_patches);

  /// 补丁 id → 来源（工具名或 'ops'）；渲染列表用。
  Map<String, String> get sources => Map<String, String>.unmodifiable(_sources);

  /// 喂入一条助手回复；编译出非空 ops 时存为一个待应用补丁（[fs] 用于
  /// 记录提出时的基底内容，apply 冲突检测用）。
  Future<void> feed(String text, {FileSystem? fs}) async {
    final List<PatchOp> ops = tryCompileOps(text);
    if (ops.isEmpty) return;
    await feedOps(ops, fs: fs);
  }

  /// 直接登记一组 ops 为一个待应用补丁，返回其序号（1 起）。
  /// 同时经 [fs] 记录每个目标文件的基底内容（apply 时比对磁盘判冲突）。
  Future<int> feedOps(
    List<PatchOp> ops, {
    String source = 'ops',
    FileSystem? fs,
  }) async {
    _seq += 1;
    final String id = 'pending-${DateTime.now().microsecondsSinceEpoch}-$_seq';
    _patches.add(DocPatch(id: id, author: PatchAuthor.ai, ops: ops));
    _sources[id] = source;
    _bases[id] = await readPendingBases(fs, ops);
    return _patches.length;
  }

  /// 丢弃第 [index] 个（1 起）待应用补丁（pending 是临时态，不落 log）。
  String reject(int index) {
    if (index < 1 || index > _patches.length) {
      return '没有第 $index 个待定补丁（/story pending 查看列表）。';
    }
    final DocPatch removed = _patches.removeAt(index - 1);
    _sources.remove(removed.id);
    _bases.remove(removed.id);
    return '已丢弃第 $index 个待定补丁（${removed.ops.length} 个文件未改动）。';
  }

  /// 应用第 [index] 个（1 起）：逐 op 经 fs 缝写文件，全部成功后 commit
  /// 进引擎并从 pending 移除。返回面向用户的说明文本。
  Future<String> apply(int index, DocEngine engine, FileSystem? fs) async {
    if (index < 1 || index > _patches.length) {
      return '没有第 $index 个待应用补丁（/story pending 查看列表）。';
    }
    final DocPatch patch = _patches[index - 1];
    final String? refusal = _unsupportedOp(patch, index);
    if (refusal != null) return refusal;
    final FileSystem? seam = fs;
    if (seam == null) return 'fs 缝不可用，无法应用。';
    return _writeAndCommit(index, patch, engine, seam);
  }

  /// v1 只支持 Insert / Replace（写文件语义）；Remove / Move 拒绝整个补丁。
  String? _unsupportedOp(DocPatch patch, int index) {
    for (final PatchOp op in patch.ops) {
      if (op is InsertBlockOp || op is ReplaceBlockOp) continue;
      return '第 $index 个补丁含 ${op.runtimeType} '
          '（删除/移动块），v1 不支持应用，请手动处理后驳回。';
    }
    return null;
  }

  Future<String> _writeAndCommit(
    int index,
    DocPatch patch,
    DocEngine engine,
    FileSystem fs,
  ) async {
    final Map<String, String?>? bases = _bases[patch.id];
    // 落盘文本按文件收集；commit 的 ops 用「apply 前 fold → 落盘后内容」
    // 经段落同步器生成（冲突合并文本同路）。引擎状态在 commit 前不变，
    // 人期间改的段落已是 fold 的一部分，sync 只补 AI 落盘的增量。
    final Map<String, String> landedText = <String, String>{};
    int conflicts = 0;
    for (final PatchOp op in patch.ops) {
      final ({String text, bool conflicted}) result = await applyPendingOp(
        fs,
        op,
        bases,
        index,
      );
      landedText[op.blockId] = result.text;
      if (result.conflicted) conflicts++;
    }
    final DocumentState before = engine.state;
    final List<PatchOp> landed = <PatchOp>[
      for (final MapEntry<String, String> entry in landedText.entries)
        ...syncFileOps(state: before, path: entry.key, newText: entry.value),
    ];
    final DocPatch removed = _patches.removeAt(index - 1);
    _sources.remove(removed.id);
    _bases.remove(removed.id);
    await engine.commit(
      DocPatch(
        id: 'story-${DateTime.now().microsecondsSinceEpoch}-a$index',
        author: PatchAuthor.ai,
        ops: landed,
      ),
    );
    if (conflicts == 0) {
      return '已应用第 $index 个补丁（${patch.ops.length} 个文件），并入故事线。';
    }
    return '已应用第 $index 个补丁（${patch.ops.length} 个文件），并入故事线；'
        '冲突：$conflicts 个文件已留双版本（$kConflictOpen 标记），请人工合并。';
  }
}

/// 渲染待应用列表（`/story pending` 输出）：序号 + 来源 + ops 摘要。
String renderStoryPending(
  List<DocPatch> patches, {
  Map<String, String> sources = const <String, String>{},
}) {
  if (patches.isEmpty) return '没有待定补丁。';
  final StringBuffer buffer = StringBuffer('待定补丁（${patches.length}）：');
  for (final (int index, DocPatch patch) in patches.indexed) {
    final String ops = patch.ops
        .map((PatchOp op) => '${op.runtimeType}(${op.blockId})')
        .join(', ');
    final String source = sources[patch.id] ?? 'ops';
    buffer.write('\n  ${index + 1}. [$source] $ops');
  }
  return buffer.toString();
}

/// 订阅会话的助手消息事件，把含 ops 块的回复喂进 [pending]。
/// 返回撤销函数（随会话子上下文释放）。
Disposer bindStoryPending(Context ctx, Session session, StoryPending pending) {
  ctx.provide('storyPending', pending);
  final FileSystem? fs = ctx.get<FileSystem>('fs');
  return session.onEvent((SessionEvent event) {
    if (event.type != kAssistantMessageEvent) return;
    unawaited(pending.feed(_assistantText(event.data), fs: fs));
  });
}

String _assistantText(Object? data) {
  if (data is! Map) return '';
  final Object? text = data['text'];
  return text is String ? text : '';
}

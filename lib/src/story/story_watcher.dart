/// 人的编辑监听：定期扫描工作目录，把引擎状态之外的文件改动登记为
/// human 补丁（设计文档 §2.4「人的编辑是一等事件」），并生成摘要通报
/// 进 [StoryNotices]（轮内注入闭环）。
///
/// 选型：**轮询 mtime** 而非 `Directory.watch`——watch 的 recursive 在
/// Linux（inotify）上不支持、FSEvents 在 macOS 上事件粒度粗且CI 时序不稳；
/// 轮询跨平台语义一致，测试可显式 `scanOnce()` 驱动，轮询间隔本身就是
/// 防抖窗（同一路径在窗口内的连续改动合并为一个 op，最终内容归因）。
///
/// 归因：AI 经工具写文件同样触发 mtime 变化，但 AI 补丁已把「写入后内容」
/// 记进引擎状态——扫描时读回内容与引擎一致即跳过，不一致才是人改的。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_doc/conatus_doc.dart';

import 'story_blocks.dart';
import 'story_notices.dart';
import 'story_scan.dart';
import 'story_sync.dart';

/// 工作目录轮询器：把人的文件改动登记为 `PatchAuthor.human` 补丁。
///
/// 首次 [scanOnce] 只建基线（现状不算编辑）；之后每次扫描把「mtime 变新
/// 且内容与引擎状态不一致」的文件合成一个 human 补丁提交，并按
/// [notices] 追加摘要通报。文件删除 v1 不记（RemoveBlockOp 的接入留给
/// 回溯语义一起设计）。
class StoryWatcher {
  /// 以目标 [engine] 与工作目录 [dir] 构造。
  StoryWatcher({
    required this.engine,
    required this.dir,
    this.telemetry,
    this.notices,
  });

  /// 补丁提交目标。
  final DocEngine engine;

  /// 被监听的工作目录（绝对路径）。
  final String dir;

  /// 降级告警出口。
  final Telemetry? telemetry;

  /// 待通报队列；null 时只记补丁不通报。
  final StoryNotices? notices;

  /// 基线：相对路径 → (mtime, 长度)。
  final Map<String, (DateTime, int)> _mtimes = <String, (DateTime, int)>{};
  int _seq = 0;
  bool _primed = false;
  bool _scanning = false;
  bool _disposed = false;

  /// 扫描一次。首次调用只建基线；重入（上一轮未扫完）直接跳过。
  Future<void> scanOnce() async {
    if (_disposed || _scanning) return;
    _scanning = true;
    try {
      await _scan();
    } finally {
      _scanning = false;
    }
  }

  /// 停止（幂等）；挂起的扫描跑完后自然停止。
  void dispose() => _disposed = true;

  Future<void> _scan() async {
    final Map<String, (DateTime, int)> now = await snapshotWorkdir(dir);
    if (!_primed) {
      _primed = true;
      _mtimes.addAll(now);
      return;
    }
    final List<({List<PatchOp> ops, String path, int added, int removed})>
    changes = await _diffOps(now);
    _mtimes
      ..clear()
      ..addAll(now);
    if (changes.isEmpty || _disposed) return;
    _seq += 1;
    await engine.commit(
      DocPatch(
        id: 'human-${DateTime.now().microsecondsSinceEpoch}-$_seq',
        author: PatchAuthor.human,
        ops: <PatchOp>[for (final c in changes) ...c.ops],
      ),
    );
    notices?.add(
      renderEditNotice(<StoryFileChange>[
        for (final c in changes)
          (path: c.path, added: c.added, removed: c.removed),
      ]),
    );
  }

  /// 与基线对比：mtime 变新的文件逐个读回归因，返回本批变化。
  Future<List<({List<PatchOp> ops, String path, int added, int removed})>>
  _diffOps(Map<String, (DateTime, int)> now) async {
    final List<({List<PatchOp> ops, String path, int added, int removed})> out =
        <({List<PatchOp> ops, String path, int added, int removed})>[];
    for (final MapEntry<String, (DateTime, int)> entry in now.entries) {
      final (DateTime, int)? before = _mtimes[entry.key];
      final bool unchanged = before != null && before == entry.value;
      if (unchanged) continue;
      final change = await _attributeOp(entry.key);
      if (change != null) out.add(change);
    }
    return out;
  }

  /// 内容归因：磁盘内容与引擎 fold（段落重建）一致 = AI 自己写的（跳过）；
  /// 不一致 = 人改的，生成段落级 ops（段落同步器；通报行数仍按行级
  /// diffLines）。读回失败（非文本等）跳过。双方经 normalizeParagraphText
  /// 规范化再比（split/render 往返会归一多余空行）。
  Future<({List<PatchOp> ops, String path, int added, int removed})?>
  _attributeOp(String path) async {
    final String? text = await _readText(path);
    if (text == null) return null;
    final DocumentState state = engine.state;
    final String oldText = renderFileText(blocksOfFile(state, path));
    if (normalizeParagraphText(oldText) == normalizeParagraphText(text)) {
      return null;
    }
    final ({int added, int removed}) diff = diffLines(oldText, text);
    return (
      ops: syncFileOps(state: state, path: path, newText: text),
      path: path,
      added: diff.added,
      removed: diff.removed,
    );
  }

  Future<String?> _readText(String path) async {
    try {
      return await File('$dir/$path').readAsString();
    } catch (error) {
      telemetry?.emit(
        TelemetryEvent(
          'story.watch_failed',
          data: <String, Object?>{'message': '读回 $path 失败：$error'},
        ),
      );
      return null;
    }
  }
}

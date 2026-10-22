/// 故事层（人机双写）薄接入：一次成功的文件编辑 = 一个补丁。
///
/// 块 = 文件的薄映射：块 id 即文件相对路径。`write_file` / `edit_file` /
/// `apply_patch` 的成功结果各产生一个 [DocPatch]（author: ai）；失败结果
/// 不记。补丁经 [provideDoc] 的引擎提交——装配了 `'sessionLog'` 服务时
/// 同步落 `doc/patch` 会话事件，否则为纯内存故事线。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'story_notices.dart';
import 'story_pending.dart';
import 'story_render.dart';
import 'story_review.dart';
import 'story_sync.dart';
import 'story_watcher.dart';

/// 产生故事补丁的编辑工具。
const Set<String> kStoryToolNames = <String>{
  'write_file',
  'edit_file',
  'apply_patch',
};

/// 提供故事层：`'doc'` 服务（[DocEngine]）+ 编辑工具观察中间件 +
/// 人的编辑监听（轮询 [watchDir]）+ 待应用补丁通道（[session] 提供时）。
///
/// [sessionId] 是 `doc/*` 事件的会话归属。装配了 `'sessionLog'` 服务时
/// 先经 [rebuildDocEngine] 从事件流重建（跨重启恢复故事线），否则起新
/// 内存引擎。[watchDir] 缺省取 `'workdir'` 服务；为 null 时不装监听。
/// [session] 提供时订阅助手消息，把含 ```` ```ops ```` 块的回复收进
/// `'storyPending'` 服务（审阅后 `/story apply` 才生效）。
/// 中间件与监听都随 [ctx] 卸载撤销；登记失败只记 telemetry
/// （`story.record_failed`），不影响工具调用本身。
Future<DocEngine> provideStory(
  Context ctx, {
  required String sessionId,
  String? watchDir,
  Duration pollInterval = const Duration(milliseconds: 500),
  Session? session,

  /// 事前审阅：挂载写工具拦截门（编辑先成待定补丁）。仅交互模式传 true；
  /// headless 没有人审，保持直写。
  bool review = false,
}) async {
  final DocEngine engine = await _restoreEngine(ctx, sessionId);
  ctx.provide('doc', engine);
  final StoryRecorder recorder = StoryRecorder(
    engine: engine,
    fs: ctx.get<FileSystem>('fs'),
    telemetry: ctx.get<Telemetry>('telemetry'),
  );
  if (session != null) {
    final StoryPending pending = StoryPending();
    ctx.onDispose(bindStoryPending(ctx, session, pending));
    if (review) {
      // 审查门必须先于 recorder 注册：先注册者在外层先命中——被拦的调用
      // 不调 next()，recorder 看不到，自然不会把待定补丁误记为 ai 补丁。
      final StoryReviewGate gate = StoryReviewGate(
        pending: pending,
        fs: ctx.get<FileSystem>('fs'),
      );
      ctx.provide('storyReview', gate);
      ctx.effect(() => gate.mount(ctx.tools));
    }
  }
  ctx.effect(() => ctx.tools.use(recorder.observe, tag: 'story'));
  final StoryNotices notices = StoryNotices();
  ctx.provide('storyNotices', notices);
  _startWatcher(
    ctx,
    engine,
    watchDir ?? ctx.get<String>('workdir'),
    pollInterval,
    notices,
  );
  return engine;
}

/// 恢复引擎：有 `'sessionLog'` 从事件流重建（含 fork 切点映射），没有则
/// 起纯内存引擎（不落事件）。
Future<DocEngine> _restoreEngine(Context ctx, String sessionId) async {
  final SessionLog? log = ctx.get<SessionLog>('sessionLog');
  if (log == null) return DocEngine(PatchLog(), sessionId: sessionId);
  return rebuildDocEngine(log, sessionId);
}

/// 装工作目录监听：轮询间隔即防抖窗；首个 interval 用于建基线。
/// 人的编辑通报追加进 [notices]（由 SteeringSource 轮内注入带走）。
void _startWatcher(
  Context ctx,
  DocEngine engine,
  String? watchDir,
  Duration interval,
  StoryNotices notices,
) {
  if (watchDir == null) return;
  final StoryWatcher watcher = StoryWatcher(
    engine: engine,
    dir: watchDir,
    telemetry: ctx.get<Telemetry>('telemetry'),
    notices: notices,
  );
  ctx.interval(() => unawaited(watcher.scanOnce()), interval);
  ctx.onDispose(watcher.dispose);
}

/// 把成功的编辑工具调用落成补丁（每个变动文件一个 op，整次调用一个补丁）。
class StoryRecorder {
  /// 以目标 [engine] 与可选的 fs / telemetry 缝构造。
  StoryRecorder({required this.engine, this.fs, this.telemetry});

  /// 补丁提交目标。
  final DocEngine engine;

  /// 读回新内容的文件系统缝；缺失时 op 文本为空串。
  final FileSystem? fs;

  /// 降级告警出口。
  final Telemetry? telemetry;

  int _seq = 0;

  /// 工具中间件：先放行，成功后登记补丁；登记失败只告警。
  Future<ToolResult> observe(
    ToolCall call,
    Future<ToolResult> Function() next,
  ) async {
    final ToolResult result = await next();
    if (result.isError || !kStoryToolNames.contains(call.name)) return result;
    try {
      await record(call, result);
    } catch (error) {
      _warn('补丁登记失败：$error');
    }
    return result;
  }

  /// 按本次调用涉及的路径组装一个补丁并提交（ops 为段落级，见
  /// story_sync.dart）。
  Future<void> record(ToolCall call, ToolResult result) async {
    final List<String> paths = storyEditedPaths(call, result);
    if (paths.isEmpty) return;
    final List<PatchOp> ops = <PatchOp>[
      for (final String path in paths) ...await _opsForFile(path),
    ];
    _seq += 1;
    await engine.commit(
      DocPatch(
        id: 'story-${DateTime.now().microsecondsSinceEpoch}-$_seq',
        author: PatchAuthor.ai,
        ops: ops,
      ),
    );
  }

  /// 单个文件的段落级 ops：读回新内容与 fold 状态对齐（段落同步器）。
  Future<List<PatchOp>> _opsForFile(String path) async {
    final String text = await _readBack(path);
    try {
      return syncFileOps(state: engine.state, path: path, newText: text);
    } catch (error) {
      // fail-safe：同步器异常不炸工具调用，退化为整块 op。
      _warn('段落同步失败（$path）：$error');
      return wholeFileOps(state: engine.state, path: path, newText: text);
    }
  }

  /// 经 fs 缝读回新内容；失败降级为空串并告警（补丁不丢，内容稍后可重建）。
  Future<String> _readBack(String path) async {
    final FileSystem? seam = fs;
    if (seam == null) return '';
    try {
      return await seam.readText(await seam.resolve(path));
    } catch (error) {
      _warn('读回 $path 失败：$error');
      return '';
    }
  }

  void _warn(String message) => telemetry?.emit(
    TelemetryEvent(
      'story.record_failed',
      data: <String, Object?>{'message': message},
    ),
  );
}

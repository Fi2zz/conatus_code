/// 每会话检查点管理器：轮次计数、绑定/解绑、`/rewind` 编排。
///
/// 服务键 `'checkpointManager'`，根上下文装配（`ConatusTuiRuntime.create`）。
/// 绑定会话时 [reset]（轮次归 0 并写 turn 0 初始快照），每轮收口后
/// [recordTurn]；[rewind] 只回滚工作区文件、不动会话与对话（v1 语义，见
/// `docs/superpowers/specs/2026-09-24-conatus-code-checkpoint-rewind-design.md`）。
///
/// 两次快照在串行链上排队（[reset] / [recordTurn] / [detach] 都经由它），
/// 因为差量必须落在基线之后：否则基线还在写，差量已按「基线缺失」分类，
/// 合成出从未存在过的混合状态。调用方因此可以不等 [reset] 返回——
/// 大工作区的全量基线可达数十秒。
library;

import 'dart:async';

import '../config/config_schema.dart';
import 'checkpoint_store.dart';
import 'checkpoint_types.dart';

/// 每会话检查点管理器。
class CheckpointManager {
  CheckpointManager({
    required CheckpointStore store,
    required CheckpointConfig config,
  }) : _store = store,
       _config = config;

  final CheckpointStore _store;
  final CheckpointConfig _config;
  String? _sessionId;
  int _turn = 0;

  /// 快照串行链：保证 [reset] 与 [recordTurn] 不交叉执行。
  ///
  /// 单次失败不毒化后续（在链内吞掉，只把错误交给返回的 Future）。
  Future<void> _chain = Future<void>.value();

  /// 解绑代数：[detach] 递增；在途的 [reset] 发现代数已变即放弃本次基线。
  int _epoch = 0;

  /// 当前绑定的会话 id；未绑定为 `null`。
  String? get sessionId => _sessionId;

  /// 当前轮次（含 turn 0 初始快照）。
  int get turn => _turn;

  /// 是否启用（`[checkpoint] enabled`）。
  bool get enabled => _config.enabled;

  /// 绑定会话：轮次归 0 并写初始快照（turn 0）。失败返回错误说明。
  ///
  /// 重绑即新时间线：会话已有检查点时先清空（旧 base/差量一并移除），
  /// 避免旧差量叠在新 base 上合成从未存在过的混合状态。
  ///
  /// 立即返回（不 await 快照落盘）：调用方可让 UI 先就绪，用返回的 Future
  /// 等基线真正就绪。大工作区的全量基线可达数十秒，不该挡住界面。
  Future<String?> reset(String sessionId, {String? lastEventId}) {
    // 会话归属与轮次同步切换：`rewind` / `list` 在基线落盘前就该看到新会话，
    // 轮次归 0（否则 UI 会显示上一条时间线的 turn 数）。
    _sessionId = sessionId;
    _turn = 0;
    return _enqueue(() => _writeBase(sessionId, lastEventId));
  }

  /// 写 turn 0 全量基线（清旧时间线后落盘）。由串行链调用。
  Future<String?> _writeBase(String sessionId, String? lastEventId) async {
    if (!enabled) return null;
    try {
      if (_store.list(sessionId).isNotEmpty) {
        await _store.clearSession(sessionId);
      }
      await _store.snapshot(sessionId, 0, lastEventId: lastEventId);
      return null;
    } catch (error) {
      return '检查点初始快照失败：$error';
    }
  }

  /// 把一个快照动作排进 [_chain]，串行执行并返回其错误说明。
  ///
  /// 入队时记下 [_epoch]；执行时若代数已变（期间发生过 [detach]），跳过动作
  /// 并返回 `null`——已解绑的会话不该在后台继续写基线。
  Future<String?> _enqueue(Future<String?> Function() action) {
    final int queued = _epoch;
    final Completer<String?> completer = Completer<String?>();
    _chain = _chain.then((_) async {
      completer.complete(queued == _epoch ? await action() : null);
    });
    return completer.future;
  }

  /// 解绑会话（幂等）。递增代数让在途的基线快照自行放弃。
  void detach() {
    _epoch++;
    _sessionId = null;
    _turn = 0;
  }

  /// 每轮收口后调用：轮次 +1 并快照。失败返回错误说明（不抛出）。
  ///
  /// 与 [reset] 共用串行链：本轮的差量一定晚于基线落盘。
  Future<String?> recordTurn({String? lastEventId}) => _enqueue(() async {
    final String? id = _sessionId;
    if (id == null) return null;
    _turn++;
    if (!enabled) return null;
    try {
      await _store.snapshot(id, _turn, lastEventId: lastEventId);
      return null;
    } catch (error) {
      return '检查点保存失败：$error';
    }
  });

  /// 可用检查点摘要（轮次升序，含有效文件数）。
  List<CheckpointInfo> list() {
    final String? id = _sessionId;
    if (id == null || !enabled) return const <CheckpointInfo>[];
    return _store.list(id);
  }

  /// 回滚 [steps] 轮（缺省 1）：目标 = 当前轮次 - steps，钳制到最早检查点。
  ///
  /// 无检查点（未启用 / 无历史）返回 `null`。恢复不动检查点目录，可反复回滚。
  Future<CheckpointRewindResult?> rewind(int steps) async {
    final String? id = _sessionId;
    if (id == null || !enabled) return null;
    final List<CheckpointInfo> infos = _store.list(id);
    if (infos.isEmpty) return null;
    final List<int> turns = <int>[
      for (final CheckpointInfo info in infos) info.turn,
    ];
    final int back = steps < 1 ? 1 : steps;
    final int target = turns.length > back
        ? turns[turns.length - 1 - back]
        : turns.first;
    final CheckpointManifest manifest = await _store.loadManifest(id, target);
    final CheckpointRestore restore = await _store.restore(id, target);
    return CheckpointRewindResult(
      turn: target,
      restore: restore,
      lastEventId: manifest.lastEventId,
    );
  }
}

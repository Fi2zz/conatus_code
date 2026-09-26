/// 每会话检查点管理器：轮次计数、绑定/解绑、`/rewind` 编排。
///
/// 服务键 `'checkpointManager'`，根上下文装配（`ConatusTuiRuntime.create`）。
/// 绑定会话时 [reset]（轮次归 0 并写 turn 0 初始快照），每轮收口后
/// [recordTurn]；[rewind] 只回滚工作区文件、不动会话与对话（v1 语义，见
/// `docs/superpowers/specs/2026-09-24-conatus-code-checkpoint-rewind-design.md`）。
library;

import '../config/config_schema.dart';
import 'checkpoint_restore.dart';
import 'checkpoint_store.dart';
import 'checkpoint_types.dart';

/// 每会话检查点管理器。
class CheckpointManager {
  CheckpointManager({required CheckpointStore store, required CheckpointConfig config})
      : _store = store,
        _config = config;

  final CheckpointStore _store;
  final CheckpointConfig _config;
  String? _sessionId;
  int _turn = 0;

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
  Future<String?> reset(String sessionId, {String? lastEventId}) async {
    _sessionId = sessionId;
    _turn = 0;
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

  /// 解绑会话（幂等）。
  void detach() {
    _sessionId = null;
    _turn = 0;
  }

  /// 每轮收口后调用：轮次 +1 并快照。失败返回错误说明（不抛出）。
  Future<String?> recordTurn({String? lastEventId}) async {
    _turn++;
    if (!enabled) return null;
    final String? id = _sessionId;
    if (id == null) return null;
    try {
      await _store.snapshot(id, _turn, lastEventId: lastEventId);
      return null;
    } catch (error) {
      return '检查点保存失败：$error';
    }
  }

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
    final CheckpointManifest manifest = _store.manifestOf(id, target);
    final CheckpointRestore restore = await restoreCheckpoint(_store, id, target);
    return CheckpointRewindResult(
      turn: target,
      restore: restore,
      lastEventId: manifest.lastEventId,
    );
  }
}

/// `/undo` `/redo` 的编排：恢复工作区文件、在切点分叉对话、暂存 prompt。
///
/// 与 `/rewind` 的分工：`/undo` 留下 [RevertStage]，`/redo` 能回到撤销前；
/// `/rewind` 是一次性回滚、没有重做。文件恢复复用 [CheckpointManager]，
/// 对话回滚沿用「`Session.fork` + `SessionStore.adopt`」的 append-only 派生。
library;

import 'dart:math' as math;

import 'package:conatus_foundation/conatus_foundation.dart';

import '../checkpoint/checkpoint_changes.dart';
import '../checkpoint/checkpoint_manager.dart';
import '../checkpoint/checkpoint_types.dart';
import 'revert_prompts.dart';
import 'revert_stage.dart';

/// 撤销 / 重做服务。
class RevertService {
  RevertService({
    required CheckpointManager checkpoint,
    required SessionStore sessions,
    Future<bool> Function(String message)? confirm,
  }) : _checkpoint = checkpoint,
       _sessions = sessions,
       _confirm = confirm;

  final CheckpointManager _checkpoint;
  final SessionStore _sessions;

  /// 覆盖工作区前的确认钩子；`null`（无交互通道）时不询问直接继续。
  final Future<bool> Function(String message)? _confirm;

  /// 撤销 [steps] 轮（缺省 1）：恢复文件 + 对话回到目标切点，并暂存 prompt。
  Future<UndoResult> undo(Session current, int steps) async {
    final int count = steps < 1 ? 1 : steps;
    if (!_checkpoint.enabled) return _undoConversationOnly(current, count);
    await _checkpoint.flush();
    final int fromTurn = _checkpoint.turn;
    final int toTurn = math.max(0, fromTurn - count);
    if (toTurn >= fromTurn) {
      throw RevertException('没有可撤销的轮次（当前第 $fromTurn 轮）。');
    }
    final bool known = _checkpoint.list().any(
      (CheckpointInfo info) => info.turn == toTurn,
    );
    if (!known) {
      throw RevertException('找不到第 $toTurn 轮检查点（可能已被裁剪）。');
    }
    await _confirmRestore(current.id, toTurn, fromTurn);
    final CheckpointRewindResult? restored = await _checkpoint.restoreTo(
      current.id,
      toTurn,
    );
    if (restored == null) {
      throw RevertException('恢复第 $toTurn 轮检查点失败，文件未改动。');
    }
    final List<String> prompts = revertPromptsAfter(
      current,
      restored.lastEventId,
    );
    return UndoResult(
      stage: RevertStage(
        originalSessionId: current.id,
        forkSessionId: _forkAt(current, restored.lastEventId),
        fromTurn: fromTurn,
        toTurn: toTurn,
        prompt: _latest(prompts),
      ),
      restore: restored.restore,
    );
  }

  /// 重做一次撤销：把文件恢复到撤销前的轮次。
  ///
  /// 会话切回由调用方做（切会话是界面职责）；checkpoint 关闭时无从恢复文件，
  /// 返回 `restored: false` 让调用方只切回原会话。
  Future<RedoResult> redo(RevertStage stage) async {
    if (!_checkpoint.enabled) return const RedoResult(restored: false);
    await _checkpoint.flush();
    final CheckpointRewindResult? restored = await _checkpoint.restoreTo(
      stage.originalSessionId,
      stage.fromTurn,
    );
    if (restored == null) {
      throw RevertException('找不到第 ${stage.fromTurn} 轮检查点，无法重做。');
    }
    return const RedoResult(restored: true);
  }

  /// checkpoint 关闭：只把对话分叉回 [count] 轮之前，文件一律不动。
  Future<UndoResult> _undoConversationOnly(Session current, int count) async {
    final String? cut = revertCutBefore(current, count);
    return UndoResult(
      stage: RevertStage(
        originalSessionId: current.id,
        forkSessionId: _forkAt(current, cut),
        fromTurn: _boundTurn(current),
        toTurn: 0,
        prompt: _latest(revertPromptsAfter(current, cut)),
      ),
      restore: const CheckpointRestore(restored: 0, deleted: 0),
    );
  }

  /// 管理器当前轮次；未绑定 [current] 时按 0。
  int _boundTurn(Session current) =>
      _checkpoint.sessionId == current.id ? _checkpoint.turn : 0;

  /// 工作区在目标区间内有改动时先确认；确认被拒则抛出。
  Future<void> _confirmRestore(String id, int toTurn, int fromTurn) async {
    final Future<bool> Function(String message)? confirm = _confirm;
    if (confirm == null) return;
    if (!await _changedBetween(id, toTurn, fromTurn)) return;
    final bool ok = await confirm(
      '工作区在第 $toTurn—$fromTurn 轮之间有改动，撤销会覆盖这些内容。继续？',
    );
    if (!ok) throw const RevertException('已取消撤销：工作区保持原样。');
  }

  /// 两轮之间是否有文件变化；读不到差异时按「可能有改动」保守处理。
  Future<bool> _changedBetween(String id, int fromTurn, int toTurn) async {
    try {
      final List<CheckpointFileChange> changes = await _checkpoint
          .changesBetween(id, fromTurn, toTurn);
      return changes.isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  /// 从 [cut] 处 fork 会话并注册；[cut] 为 `null` 时建全新空会话。
  String _forkAt(Session current, String? cut) {
    if (cut == null) return _sessions.create().id;
    final Session fork = current.fork(
      fromEventId: cut,
      id: 'session_${newUuidV4()}',
    );
    return _sessions.adopt(fork).id;
  }

  static String _latest(List<String> prompts) =>
      prompts.isEmpty ? '' : prompts.last;
}

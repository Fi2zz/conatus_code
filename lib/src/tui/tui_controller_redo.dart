part of 'tui_controller.dart';

/// `/redo`：恢复撤销前的文件并切回原会话。
extension _RedoCommands on ConatusTuiController {
  Future<void> _runRedo() async {
    if (_revertInFlight) {
      showSystemNotice('正在撤销/重做，请稍候。');
      return;
    }
    final RevertStage? stage = _revertStage;
    final CheckpointManager? checkpoint = _app.get<CheckpointManager>(
      'checkpointManager',
    );
    if (stage == null) {
      showSystemNotice('没有可重做的撤销操作（撤销后发新 prompt 即提交）。');
      return;
    }
    if (checkpoint == null) {
      showSystemNotice('重做不可用：未装配检查点。');
      return;
    }
    if (busy) {
      showSystemNotice('有在途轮次，请稍候再试。');
      return;
    }
    if (_sessionId != stage.forkSessionId) {
      showSystemNotice(
        '重做只能在撤销后的会话里执行：请先 /session ${stage.forkSessionId} '
        '（切会话会丢弃本次撤销点）。',
      );
      return;
    }
    _revertInFlight = true;
    try {
      if (checkpoint.enabled &&
          !await _confirmRevert(
            '重做会把工作区恢复到第 ${stage.fromTurn} 轮：撤销后新建 / 修改的文件'
            '会被删除或覆盖，继续？',
          )) {
        showSystemNotice('已取消重做：工作区保持原样。');
        return;
      }
      await _applyRedo(stage, checkpoint);
    } on RevertException catch (error) {
      showSystemNotice('重做失败：${error.message}');
    } catch (error) {
      // flush / restoreTo 可能抛 CheckpointException 或 IO：TUI 是 unawaited 调用，
      // 漏出去就是未处理的异步错误。
      showSystemNotice('重做失败：$error');
    } finally {
      _revertInFlight = false;
      _refresh();
    }
  }

  /// 重做的执行体：恢复文件 → 切回原会话 → 清撤销点与待回填。
  Future<void> _applyRedo(
    RevertStage stage,
    CheckpointManager checkpoint,
  ) async {
    final RedoResult result = await RevertService(
      checkpoint: checkpoint,
      sessions: _sessions,
    ).redo(stage);
    final String announce = _redoAnnounce(stage, result.restored);
    if (_sessionId == stage.originalSessionId) {
      showSystemNotice(announce);
    } else if (!await switchSession(
      stage.originalSessionId,
      announce: announce,
      system: true,
    )) {
      showSystemNotice(
        '重做未完成：工作区已恢复到第 ${stage.fromTurn} 轮，'
        '但会话未切回（可重试 /redo）。',
      );
      return;
    }
    _revertStage = null;
    _prefill = null;
    _refresh();
  }

  String _redoAnnounce(RevertStage stage, bool restored) => restored
      ? '已重做：工作区恢复到第 ${stage.fromTurn} 轮，'
            '切回会话 ${stage.originalSessionId}（/undo 可再撤销）。'
      : '已重做：checkpoint 已关闭，仅切回会话 '
            '${stage.originalSessionId}（文件未改动）。';
}

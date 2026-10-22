part of 'tui_controller.dart';

/// 撤销确认的等待上限：无人应答按取消处理（与审批门同一安全取向）。
const Duration kRevertConfirmTimeout = Duration(minutes: 2);

/// `/undo` 确认选项 id：继续撤销。
const String kRevertConfirmId = 'undo';

/// `/undo` `/redo` 的命令实现：文件恢复 + 对话分叉 + prompt 回填。
extension _RevertCommands on ConatusTuiController {
  Future<void> _runUndo(int steps) async {
    final Session? session = _session;
    final CheckpointManager? checkpoint = _app.get<CheckpointManager>(
      'checkpointManager',
    );
    if (session == null) {
      _notice('撤销不可用：会话尚未绑定。');
      return;
    }
    if (checkpoint == null) {
      _notice('撤销不可用：未装配检查点。');
      return;
    }
    if (busy) {
      _notice('有在途轮次，请稍候再试。');
      return;
    }
    await _checkpointBase;
    final int before = _promptCount(session);
    try {
      final UndoResult result = await RevertService(
        checkpoint: checkpoint,
        sessions: _sessions,
        confirm: _confirmRevert,
      ).undo(session, steps);
      await _applyUndo(session, result, checkpoint.enabled, before);
    } on RevertException catch (error) {
      _notice('撤销失败：${error.message}');
    } catch (error) {
      _notice('撤销失败：$error');
    }
  }

  /// 落实撤销结果：切到 fork 会话、提示其余 prompt、回填输入框。
  Future<void> _applyUndo(
    Session source,
    UndoResult result,
    bool files,
    int promptsBefore,
  ) async {
    final RevertStage stage = result.stage;
    _revertStage = stage;
    final int undone =
        promptsBefore - _promptCount(_sessions.get(stage.forkSessionId));
    await switchSession(
      stage.forkSessionId,
      announce: _undoAnnounce(stage, result.restore, files),
    );
    if (undone > 1) {
      _notice(
        '另有 ${undone - 1} 条更早的 prompt 未回填'
        '（原会话 ${source.id} 保留，/sessions 可切回）。',
      );
    }
    if (stage.prompt.isNotEmpty) prefillInput(stage.prompt);
  }

  String _undoAnnounce(
    RevertStage stage,
    CheckpointRestore restore,
    bool files,
  ) {
    if (!files) {
      return '已撤销对话到第 ${stage.toTurn} 轮之前'
          '（checkpoint 已关闭，仅回滚对话、文件未改动），'
          '新会话 ${stage.forkSessionId}。';
    }
    final int rounds = stage.fromTurn - stage.toTurn;
    return '已撤销 $rounds 轮，工作区回到第 ${stage.toTurn} 轮'
        '（恢复 ${restore.restored}、删除 ${restore.deleted} 个文件），'
        '对话已回到该轮，新会话 ${stage.forkSessionId}（/redo 可恢复）。';
  }

  Future<void> _runRedo() async {
    final RevertStage? stage = _revertStage;
    final CheckpointManager? checkpoint = _app.get<CheckpointManager>(
      'checkpointManager',
    );
    if (stage == null) {
      _notice('没有可重做的撤销操作（撤销后发新 prompt 即提交）。');
      return;
    }
    if (checkpoint == null) {
      _notice('重做不可用：未装配检查点。');
      return;
    }
    if (busy) {
      _notice('有在途轮次，请稍候再试。');
      return;
    }
    try {
      final RedoResult result = await RevertService(
        checkpoint: checkpoint,
        sessions: _sessions,
      ).redo(stage);
      final String announce = _redoAnnounce(stage, result.restored);
      if (_sessionId == stage.originalSessionId) {
        _notice(announce);
      } else if (!await switchSession(
        stage.originalSessionId,
        announce: announce,
      )) {
        return;
      }
      _revertStage = null;
      _refresh();
    } on RevertException catch (error) {
      _notice('重做失败：${error.message}');
    }
  }

  String _redoAnnounce(RevertStage stage, bool restored) => restored
      ? '已重做：工作区恢复到第 ${stage.fromTurn} 轮，'
            '切回会话 ${stage.originalSessionId}（/undo 可再撤销）。'
      : '已重做：checkpoint 已关闭，仅切回会话 '
            '${stage.originalSessionId}（文件未改动）。';

  /// 覆盖工作区前的确认：优先用注入钩子，否则弹选项浮层（超时视为取消）。
  Future<bool> _confirmRevert(String message) async {
    final Future<bool> Function(String message)? hook = confirmRevert;
    if (hook != null) return hook(message);
    final String? picked = await choice.ask(
      TuiChoiceRequest(
        title: message,
        choices: const <TuiChoice>[
          TuiChoice(id: kRevertConfirmId, label: '继续撤销'),
          TuiChoice(id: 'cancel', label: '取消'),
        ],
      ),
      timeout: kRevertConfirmTimeout,
    );
    return picked == kRevertConfirmId;
  }

  int _promptCount(Session? session) {
    if (session == null) return 0;
    return session.events
        .where((SessionEvent event) => event.type == kUserMessageEvent)
        .length;
  }

  void _notice(String text) {
    transcript.add(TuiRole.system, text);
    _refresh();
  }
}

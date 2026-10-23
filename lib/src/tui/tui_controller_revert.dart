part of 'tui_controller.dart';

/// 撤销确认的等待上限：无人应答按取消处理（与审批门同一安全取向）。
const Duration kRevertConfirmTimeout = Duration(minutes: 2);

/// `/undo` 确认选项 id：继续撤销。
const String kRevertConfirmId = 'undo';

/// `/undo` `/redo` 的命令实现：文件恢复 + 对话分叉 + prompt 回填。
extension _RevertCommands on ConatusTuiController {
  /// `/undo [N]` 的参数解析：非正整数给用法提示，不静默按 1 处理。
  Future<void> _runUndoArg(String arg) async {
    final String text = arg.trim();
    final int? steps = text.isEmpty ? 1 : int.tryParse(text);
    if (steps == null || steps < 1) {
      showSystemNotice('用法：/undo [N]（N 为正整数，缺省 1）。');
      return;
    }
    await undo(steps);
  }

  Future<void> _runUndo(int steps) async {
    if (_revertInFlight) {
      showSystemNotice('正在撤销/重做，请稍候。');
      return;
    }
    final Session? session = _session;
    final CheckpointManager? checkpoint = _app.get<CheckpointManager>(
      'checkpointManager',
    );
    if (session == null || checkpoint == null) {
      showSystemNotice(session == null ? '撤销不可用：会话尚未绑定。' : '撤销不可用：未装配检查点。');
      return;
    }
    if (busy) {
      showSystemNotice('有在途轮次，请稍候再试。');
      return;
    }
    // busy 判定到置位之间没有 await：submit 无法在这一窗口里插进来。
    _revertInFlight = true;
    try {
      await _performUndo(session, checkpoint, steps);
    } on RevertException catch (error) {
      showSystemNotice('撤销失败：${error.message}');
    } catch (error) {
      // 恢复中途抛错时工作区状态未知：撤销点一并清掉，避免 /redo 回到错误基线。
      _revertStage = null;
      _prefill = null;
      showSystemNotice('撤销失败：$error（工作区可能已变化，撤销点已清除，请检查）');
    } finally {
      _revertInFlight = false;
      _refresh();
    }
  }

  /// 撤销执行体：等基线 → 服务恢复/分叉 → 切会话与回填。
  Future<void> _performUndo(
    Session session,
    CheckpointManager checkpoint,
    int steps,
  ) async {
    await _checkpointBase;
    final int before = _promptCount(session);
    final UndoResult result = await RevertService(
      checkpoint: checkpoint,
      sessions: _sessions,
      confirm: _confirmRevert,
    ).undo(session, steps);
    await _applyUndo(session, result, checkpoint.enabled, before);
  }

  /// 落实撤销结果：先切会话，成功后才记撤销点；切不过去就补偿工作区。
  Future<void> _applyUndo(
    Session source,
    UndoResult result,
    bool checkpointsOn,
    int promptsBefore,
  ) async {
    final RevertStage stage = result.stage;
    final int undone =
        promptsBefore - _promptCount(_sessions.get(stage.forkSessionId));
    final int rounds = checkpointsOn && stage.fromTurn > stage.toTurn
        ? stage.fromTurn - stage.toTurn
        : (undone > 0 ? undone : 1);
    final bool switched = await switchSession(
      stage.forkSessionId,
      announce: _undoAnnounce(stage, result.restore, checkpointsOn, rounds),
      system: true,
    );
    if (!switched) {
      await _abandonUndo(stage, checkpointsOn);
      return;
    }
    _revertStage = stage;
    if (undone > 1) {
      showSystemNotice(
        '另有 ${undone - 1} 条更早的 prompt 未回填'
        '（原会话 ${source.id} 保留，/sessions 可切回）。',
      );
    }
    if (stage.prompt.isNotEmpty) prefillInput(stage.prompt);
  }

  /// 切会话失败：工作区已经被回滚过，恢复到撤销前的轮次并清掉撤销点。
  Future<void> _abandonUndo(RevertStage stage, bool checkpointsOn) async {
    _revertStage = null;
    _prefill = null;
    if (!checkpointsOn) {
      showSystemNotice('撤销未完成：会话未切换（checkpoint 已关闭，文件未改动）。');
      return;
    }
    final String? error = await _restoreWorkspace(
      stage.originalSessionId,
      stage.fromTurn,
    );
    if (error == null) {
      showSystemNotice('撤销未完成：会话未切换，已把工作区恢复到第 ${stage.fromTurn} 轮。');
    } else {
      showSystemNotice('撤销未完成：会话未切换，补偿恢复失败（$error），请检查工作区。');
    }
  }

  /// 恢复指定会话的轮次；失败返回原因，成功返回 `null`。
  Future<String?> _restoreWorkspace(String sessionId, int turn) async {
    final CheckpointManager? checkpoint = _app.get<CheckpointManager>(
      'checkpointManager',
    );
    if (checkpoint == null) return '未装配检查点';
    return compensateRevertWorkspace(checkpoint, sessionId, turn);
  }

  String _undoAnnounce(
    RevertStage stage,
    CheckpointRestore restore,
    bool checkpointsOn,
    int rounds,
  ) {
    if (!checkpointsOn) {
      return '已撤销 $rounds 轮对话'
          '（checkpoint 已关闭，仅回滚对话、文件未改动），'
          '新会话 ${stage.forkSessionId}。';
    }
    return '已撤销 $rounds 轮，工作区回到第 ${stage.toTurn} 轮'
        '（恢复 ${restore.restored}、删除 ${restore.deleted} 个文件），'
        '对话已回到该轮，新会话 ${stage.forkSessionId}（/redo 可恢复）。';
  }

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
}

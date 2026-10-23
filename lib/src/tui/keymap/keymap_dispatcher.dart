/// 全局按键 dispatcher：处理单键动作与 `<leader>` 两段式（带超时）。
library;

import 'dart:async';

import 'package:nocterm/nocterm.dart';

import 'keymap.dart';

/// 把按键事件翻译成动作 ID；leader 前缀在内部暂存。
class KeymapDispatcher {
  KeymapDispatcher(
    this.keymap, {
    this.leaderTimeout = const Duration(seconds: 2),
  });

  /// 键位表。
  final Keymap keymap;

  /// 等待第二段按键的窗口；超时自动复位。
  final Duration leaderTimeout;

  Timer? _timer;
  bool _leaderPending = false;

  /// leader 已按下、正在等第二段按键。
  bool get leaderPending => _leaderPending;

  /// 返回命中的动作 ID；leader 前缀本身与未命中返回 `null`。
  ///
  /// 调用方可用 [leaderPending] 判断「虽无动作但按键已被吞掉」（刚按下
  /// leader，或 leader 后按了未映射的键）。
  String? dispatch(KeyboardEvent event) {
    if (_leaderPending) {
      _reset();
      return keymap.actionForLeaderKey(event);
    }
    if (keymap.isLeader(event)) {
      _leaderPending = true;
      _timer = Timer(leaderTimeout, _reset);
      return null;
    }
    return keymap.actionFor(event);
  }

  /// 取消待决 leader 并释放计时器。
  void dispose() => _reset();

  void _reset() {
    _timer?.cancel();
    _timer = null;
    _leaderPending = false;
  }
}

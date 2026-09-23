/// 权限模式选择浮层状态：三档模式、当前模式标记、选中与确认。
///
/// 渲染与按键由根组件驱动（见 `tui.dart`）；本状态只管选中与确认。
library;

import 'dart:async';

import 'tui_permission.dart';

/// 权限模式选择浮层状态。
class TuiPermissionPrompt {
  TuiPermissionPrompt({this.onChanged});

  /// 状态变化回调（组件据此重绘）。
  void Function()? onChanged;

  TuiPermissionMode _current = TuiPermissionMode.askWhenNeeded;
  int _index = 0;
  bool _open = false;
  Completer<TuiPermissionMode?>? _pending;

  /// 浮层是否可见。
  bool get open => _open;

  /// 当前权限模式（用于渲染 `← 当前`）。
  TuiPermissionMode get current => _current;

  /// 当前选中下标。
  int get index => _index;

  /// 当前选中模式。
  TuiPermissionMode get selected => TuiPermissionMode.values[_index];

  /// 打开面板并等待用户选中（Enter）或取消（Esc）；取消返回 `null`。
  Future<TuiPermissionMode?> choose(TuiPermissionMode current) {
    _current = current;
    final Completer<TuiPermissionMode?> completer =
        Completer<TuiPermissionMode?>();
    _pending = completer;
    _index = TuiPermissionMode.values.indexOf(current);
    if (_index < 0) {
      _index = 0;
    }
    _open = true;
    onChanged?.call();
    return completer.future;
  }

  /// 确认当前选中项并关闭（Enter）。
  void confirm() {
    final Completer<TuiPermissionMode?>? pending = _pending;
    final TuiPermissionMode mode = selected;
    close();
    if (pending != null && !pending.isCompleted) {
      pending.complete(mode);
    }
  }

  /// 取消选择并关闭（Esc）。
  void cancel() {
    final Completer<TuiPermissionMode?>? pending = _pending;
    close();
    if (pending != null && !pending.isCompleted) {
      pending.complete(null);
    }
  }

  /// 移动光标（越界钳制）。
  void move(int delta) {
    const List<TuiPermissionMode> values = TuiPermissionMode.values;
    int next = _index + delta;
    if (next < 0) {
      next = 0;
    } else if (next >= values.length) {
      next = values.length - 1;
    }
    _index = next;
    onChanged?.call();
  }

  /// 关闭面板。
  void close() {
    _open = false;
    onChanged?.call();
  }
}

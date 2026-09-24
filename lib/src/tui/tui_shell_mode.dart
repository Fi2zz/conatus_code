/// shell 模式（对齐 OpenCode）：提示符打 `!` 进入，执行一条后自动退出，
/// Esc 退出且不执行。状态机只管模式进出与提交文本，不碰 UI。
library;

/// shell 模式输入框占位提示。
String shellInputPlaceholder() => '输入 shell 命令，Esc 退出';

/// shell 模式状态栏操作提示。
String shellStatusHint() => 'shell 模式 | [Enter] 执行 | [Esc] 退出';

/// shell 模式状态机。
class TuiShellMode {
  bool _active = false;

  /// 当前是否处于 shell 模式（输入框显示 `!` 前缀）。
  bool get active => _active;

  /// 输入以 `!` 开头且尚未进入 shell 模式 → 进入并吃掉前缀（返回 true）。
  bool consumeBang(String text) {
    if (_active || !text.startsWith('!')) {
      return false;
    }
    _active = true;
    return true;
  }

  /// 主动进入 shell 模式（菜单 / 程序化触发）。
  void enter() => _active = true;

  /// 退出 shell 模式（Esc、执行后）。
  void exit() => _active = false;

  /// 提交：退出模式并返回带 `!` 前缀的命令行；空命令返回空串（不提交）。
  String submit(String command) {
    _active = false;
    final String text = command.trim();
    return text.isEmpty ? '' : '!$text';
  }
}

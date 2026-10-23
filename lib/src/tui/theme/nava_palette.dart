/// TUI 主题调色板：把界面里散落的颜色收敛成一组语义 token。
///
/// 默认调色板逐项等于引入主题层之前的硬编码颜色（`Colors.blue` 输入框、
/// `Colors.magenta` shell 框、`Color.fromRGB(30, 40, 60)` 选中底色等），
/// 因此换主题只改取色来源，不改布局与文案。
library;

import 'package:nocterm/nocterm.dart';

import '../tui_message.dart';

/// 一套主题颜色。
class NavaPalette {
  const NavaPalette({
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.success,
    required this.warning,
    required this.error,
    required this.border,
    required this.panel,
    required this.selected,
    required this.selectedText,
    required this.inputBorder,
    required this.shellBorder,
    required this.background,
    required this.info,
    required this.danger,
    required this.prompt,
    required this.highlight,
    required this.message,
  });

  /// 正文。
  final Color text;

  /// 次要文字 / 说明。
  final Color muted;

  /// 更暗的提示（思考过程、阶段行）。
  final Color faint;

  /// 强调色（面板标题 / 边框）。
  final Color accent;

  /// 成功 / 已完成。
  final Color success;

  /// 警告 / 当前标记。
  final Color warning;

  /// 失败。
  final Color error;

  /// 浮层边框。
  final Color border;

  /// 浮层底色。
  final Color panel;

  /// 选中行底色。
  final Color selected;

  /// 选中行文字。
  final Color selectedText;

  /// 普通输入框边框。
  final Color inputBorder;

  /// shell 模式输入框边框。
  final Color shellBorder;

  /// 大面积背景（团队状态栏等）。
  final Color background;

  /// 信息色（工具输出 / 团队泳道 / diff 头）。
  final Color info;

  /// 危险色（diff 删除行）。
  final Color danger;

  /// 输入提示符 `> `。
  final Color prompt;

  /// 高亮色（命令名 / 聚焦标签）。
  final Color highlight;

  /// 屏上消息角色 → 颜色。
  final Map<TuiRole, Color> message;
}

/// 默认主题：与引入主题层之前的硬编码颜色逐项一致。
const NavaPalette navaDefaultPalette = NavaPalette(
  text: Colors.white,
  muted: Colors.gray,
  faint: Colors.brightBlack,
  accent: Colors.brightBlue,
  success: Colors.brightGreen,
  warning: Colors.brightYellow,
  error: Colors.red,
  border: Colors.brightBlue,
  panel: Color.fromRGB(20, 20, 40),
  selected: Color.fromRGB(30, 40, 60),
  selectedText: Colors.brightWhite,
  inputBorder: Colors.blue,
  shellBorder: Colors.magenta,
  background: Color.fromRGB(0, 20, 40),
  info: Colors.cyan,
  danger: Colors.brightRed,
  prompt: Colors.green,
  highlight: Colors.brightCyan,
  message: <TuiRole, Color>{
    TuiRole.user: Colors.white,
    TuiRole.assistant: Colors.white,
    TuiRole.tool: Colors.cyan,
    TuiRole.plan: Colors.brightBlue,
    TuiRole.thinking: Colors.brightBlack,
    TuiRole.stage: Colors.brightBlack,
    TuiRole.system: Colors.yellow,
    TuiRole.nav: Colors.magenta,
  },
);

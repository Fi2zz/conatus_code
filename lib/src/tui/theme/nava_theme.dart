/// 内置主题注册表：`default` / `dark` / `light` / `tokyonight`。
///
/// 只提供内置主题，不读取用户主题 JSON；未知主题名回落到 `default`。
library;

import 'package:nocterm/nocterm.dart';

import '../tui_message.dart';
import 'nava_palette.dart';

/// 深色主题（更高对比，边框偏青）。
const NavaPalette _darkPalette = NavaPalette(
  text: Colors.white,
  muted: Colors.gray,
  faint: Colors.brightBlack,
  accent: Colors.brightCyan,
  success: Colors.green,
  warning: Colors.yellow,
  error: Colors.red,
  border: Colors.cyan,
  panel: Color.fromRGB(18, 18, 24),
  selected: Color.fromRGB(40, 50, 70),
  selectedText: Colors.brightWhite,
  inputBorder: Colors.cyan,
  shellBorder: Colors.magenta,
  background: Color.fromRGB(10, 10, 14),
  info: Colors.cyan,
  danger: Colors.brightRed,
  prompt: Colors.green,
  highlight: Colors.brightCyan,
  message: <TuiRole, Color>{
    TuiRole.user: Colors.white,
    TuiRole.assistant: Colors.white,
    TuiRole.tool: Colors.cyan,
    TuiRole.plan: Colors.brightCyan,
    TuiRole.thinking: Colors.brightBlack,
    TuiRole.stage: Colors.brightBlack,
    TuiRole.system: Colors.yellow,
    TuiRole.nav: Colors.magenta,
  },
);

/// 浅色主题（亮底深字）。
const NavaPalette _lightPalette = NavaPalette(
  text: Color(0x1E1E28),
  muted: Color(0x6A6A78),
  faint: Color(0x8A8A98),
  accent: Color(0x2D5AB4),
  success: Color(0x2E8B57),
  warning: Color(0xA87800),
  error: Color(0xBE323C),
  border: Color(0x2D5AB4),
  panel: Color(0xEBEEF5),
  selected: Color(0xD2E1F5),
  selectedText: Color(0x0A1428),
  inputBorder: Color(0x2D5AB4),
  shellBorder: Color(0x963096),
  background: Color(0xFAFAFC),
  info: Color(0x147882),
  danger: Color(0xBE323C),
  prompt: Color(0x2E8B57),
  highlight: Color(0x146EA0),
  message: <TuiRole, Color>{
    TuiRole.user: Color(0x1E1E28),
    TuiRole.assistant: Color(0x1E1E28),
    TuiRole.tool: Color(0x147882),
    TuiRole.plan: Color(0x2D5AB4),
    TuiRole.thinking: Color(0x8A8A98),
    TuiRole.stage: Color(0x8A8A98),
    TuiRole.system: Color(0xA87800),
    TuiRole.nav: Color(0x963096),
  },
);

/// Tokyo Night 配色。
const NavaPalette _tokyoNightPalette = NavaPalette(
  text: Color(0xC0CAF5),
  muted: Color(0x565F89),
  faint: Color(0x414868),
  accent: Color(0x7AA2F7),
  success: Color(0x9ECE6A),
  warning: Color(0xE0AF68),
  error: Color(0xF7768E),
  border: Color(0x7AA2F7),
  panel: Color(0x24283B),
  selected: Color(0x292E42),
  selectedText: Color(0xC0CAF5),
  inputBorder: Color(0x7AA2F7),
  shellBorder: Color(0xBB9AF7),
  background: Color(0x1A1B26),
  info: Color(0x7DCFFF),
  danger: Color(0xF7768E),
  prompt: Color(0x9ECE6A),
  highlight: Color(0x7DCFFF),
  message: <TuiRole, Color>{
    TuiRole.user: Color(0xC0CAF5),
    TuiRole.assistant: Color(0xC0CAF5),
    TuiRole.tool: Color(0x7DCFFF),
    TuiRole.plan: Color(0x7AA2F7),
    TuiRole.thinking: Color(0x565F89),
    TuiRole.stage: Color(0x565F89),
    TuiRole.system: Color(0xE0AF68),
    TuiRole.nav: Color(0xBB9AF7),
  },
);

/// 当前主题与内置主题表。
class NavaTheme {
  const NavaTheme._();

  static const Map<String, NavaPalette> _builtins = <String, NavaPalette>{
    'default': navaDefaultPalette,
    'dark': _darkPalette,
    'light': _lightPalette,
    'tokyonight': _tokyoNightPalette,
  };

  static const String _fallback = 'default';
  static String _current = _fallback;

  /// 当前调色板。
  static NavaPalette get palette => _builtins[_current] ?? navaDefaultPalette;

  /// 当前主题名（未知名回落为 `default`）。
  static String get current => _current;

  /// 内置主题名（按展示顺序）。
  static List<String> get names => _builtins.keys.toList(growable: false);

  /// 切换主题；未知名字回落到 [names] 的第一项 `default`。
  static void use(String name) {
    _current = _builtins.containsKey(name) ? name : _fallback;
  }
}

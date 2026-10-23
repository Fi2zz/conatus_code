/// 单个键位绑定：逻辑键 + 修饰键，以及文本形式的解析。
library;

import 'package:nocterm/nocterm.dart';

/// 一个可配置按键：`ctrl+x` / `alt+enter` / `f1` 这类组合。
class KeyBinding {
  const KeyBinding(
    this.key, {
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  /// 逻辑键。
  final LogicalKey key;

  /// Ctrl / Shift / Alt / Meta 修饰键。
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  /// 事件是否精确匹配本绑定（修饰键也必须一致）。
  bool matches(KeyboardEvent event) =>
      event.logicalKey == key &&
      event.isControlPressed == ctrl &&
      event.isShiftPressed == shift &&
      event.isAltPressed == alt &&
      event.isMetaPressed == meta;

  /// 规范展示形式（`ctrl+shift+tab`）；解析时大小写与修饰键顺序都不敏感。
  String get label => <String>[
    if (ctrl) 'ctrl',
    if (shift) 'shift',
    if (alt) 'alt',
    if (meta) 'meta',
    keyLabel(key),
  ].join('+');

  @override
  bool operator ==(Object other) =>
      other is KeyBinding &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.shift == shift &&
      other.alt == alt &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(key.keyId, ctrl, shift, alt, meta);

  @override
  String toString() => 'KeyBinding($label)';
}

/// 解析键位文本；`none` / `false` / 无法识别的键名返回 `null`。
///
/// `<leader>` 前缀只用于标记「两段式」——返回的是后续那一段的绑定，
/// 先按 leader 再按该键由 `KeymapDispatcher` 负责。[leader] 仅用于调用方
/// 表达「已配置 leader」的语义，不参与单键解析。
KeyBinding? parseKeyBinding(String text, {LogicalKey? leader}) {
  String raw = text.trim().toLowerCase();
  if (_disabledKey(raw)) {
    return null;
  }
  if (raw.startsWith(kLeaderPrefix)) {
    raw = raw.substring(kLeaderPrefix.length).trim();
  }
  if (raw.isEmpty) {
    return null;
  }
  final List<String> parts = raw.split('+');
  final LogicalKey? token = _namedKey(parts.last);
  final ({bool ctrl, bool shift, bool alt, bool meta})? modifiers = _modifiers(
    parts,
  );
  if (token == null || modifiers == null) {
    return null;
  }
  return KeyBinding(
    token,
    ctrl: modifiers.ctrl,
    shift: modifiers.shift,
    alt: modifiers.alt,
    meta: modifiers.meta,
  );
}

/// `<leader>` 文本前缀。
const String kLeaderPrefix = '<leader>';

/// `none` / `false` 表示显式关闭。
bool _disabledKey(String raw) => raw == 'none' || raw == 'false';

({bool ctrl, bool shift, bool alt, bool meta})? _modifiers(List<String> parts) {
  bool ctrl = false;
  bool shift = false;
  bool alt = false;
  bool meta = false;
  for (final String part in parts.take(parts.length - 1)) {
    switch (part) {
      case 'ctrl' || 'control':
        ctrl = true;
      case 'shift':
        shift = true;
      case 'alt' || 'option' || 'opt':
        alt = true;
      case 'meta' || 'cmd' || 'command' || 'super':
        meta = true;
      default:
        return null;
    }
  }
  return (ctrl: ctrl, shift: shift, alt: alt, meta: meta);
}

/// 按键名 → 逻辑键；字母与数字按字符码动态构造（与常量等价）。
LogicalKey? _namedKey(String token) {
  if (token.length == 1) {
    final int code = token.codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7A) {
      return LogicalKey(code, 'key${String.fromCharCode(code - 0x20)}');
    }
    if (code >= 0x30 && code <= 0x39) {
      return LogicalKey(code, 'digit$token');
    }
  }
  return _namedKeys[token];
}

/// 键位展示名：字母 / 数字还原成字符，其余按可读名映射。
String keyLabel(LogicalKey key) {
  final int id = key.keyId;
  if (id >= 0x61 && id <= 0x7A) {
    return String.fromCharCode(id);
  }
  if (id >= 0x30 && id <= 0x39) {
    return String.fromCharCode(id);
  }
  return _labels[key.debugName] ?? key.debugName;
}

// REASON: 键位名表是静态映射，集中在一处便于解析与展示共享同一套名字。
const Map<String, LogicalKey> _namedKeys = <String, LogicalKey>{
  'enter': LogicalKey.enter,
  'return': LogicalKey.enter,
  'esc': LogicalKey.escape,
  'escape': LogicalKey.escape,
  'tab': LogicalKey.tab,
  'space': LogicalKey.space,
  'backspace': LogicalKey.backspace,
  'delete': LogicalKey.delete,
  'del': LogicalKey.delete,
  'up': LogicalKey.arrowUp,
  'down': LogicalKey.arrowDown,
  'left': LogicalKey.arrowLeft,
  'right': LogicalKey.arrowRight,
  'home': LogicalKey.home,
  'end': LogicalKey.end,
  'pageup': LogicalKey.pageUp,
  'pagedown': LogicalKey.pageDown,
  'insert': LogicalKey.insert,
  'f1': LogicalKey.f1,
  'f2': LogicalKey.f2,
  'f3': LogicalKey.f3,
  'f4': LogicalKey.f4,
  'f5': LogicalKey.f5,
  'f6': LogicalKey.f6,
  'f7': LogicalKey.f7,
  'f8': LogicalKey.f8,
  'f9': LogicalKey.f9,
  'f10': LogicalKey.f10,
  'f11': LogicalKey.f11,
  'f12': LogicalKey.f12,
  'minus': LogicalKey.minus,
  '-': LogicalKey.minus,
  'equal': LogicalKey.equal,
  '=': LogicalKey.equal,
  'comma': LogicalKey.comma,
  ',': LogicalKey.comma,
  'period': LogicalKey.period,
  '.': LogicalKey.period,
  'slash': LogicalKey.slash,
  '/': LogicalKey.slash,
  'semicolon': LogicalKey.semicolon,
  ';': LogicalKey.semicolon,
};

const Map<String, String> _labels = <String, String>{
  'arrowUp': 'up',
  'arrowDown': 'down',
  'arrowLeft': 'left',
  'arrowRight': 'right',
  'escape': 'esc',
  'pageUp': 'pageup',
  'pageDown': 'pagedown',
  'space': 'space',
};

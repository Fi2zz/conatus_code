/// 选区复制：OSC52 + macOS 原生 pbcopy 双通道。
///
/// 手动复制键与「选区完成自动复制」（copy-on-select，对齐 Kimi Code
/// 的默认体验）都经此入口：nocterm 的 [ClipboardManager.copy] 维护应用
/// 内缓冲并尝试 OSC52（部分终端需用户开启"允许访问剪贴板"才生效），
/// macOS 再追加一次 `pbcopy` 直写系统剪贴板（NSPasteboard），绕过终端
/// 的 OSC52 权限限制，保证选中后随处可 Cmd+V。
library;

import 'dart:io';

import 'package:nocterm/nocterm.dart';

/// 把 [text] 写入系统剪贴板；空文本忽略。返回是否至少内部缓冲已更新。
Future<bool> copySelectionToSystemClipboard(String text) async {
  if (text.isEmpty) {
    return false;
  }
  final bool buffered = ClipboardManager.copy(text);
  if (Platform.isMacOS) {
    await _pbcopy(text);
  }
  return buffered;
}

/// macOS 原生剪贴板写入；pbcopy 缺失或失败静默（OSC52 通道已兜底）。
Future<void> _pbcopy(String text) async {
  try {
    final Process process = await Process.start('pbcopy', const <String>[]);
    process.stdin.write(text);
    await process.stdin.close();
    await process.exitCode;
  } on ProcessException {
    // pbcopy 是 macOS 系统自带；缺失时忽略。
  }
}

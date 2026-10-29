/// 读取系统剪贴板文本（同步）。
///
/// nocterm 的 bracketed paste 会把内容写进 [ClipboardManager] 再合成 Ctrl+V；
/// 但不少终端把 Ctrl+V 直接当普通按键（0x16），此时内部剪贴板为空。这里补一条
/// 读系统剪贴板的兜底，让 Ctrl+V 在终端未走 bracketed paste 时也能粘贴。
library;

import 'dart:io';

/// 剪贴板文本上限（字符）；防止一次粘贴把超大内容灌进输入框。
const int kClipboardTextMaxChars = 200000;

/// 读取系统剪贴板文本；不可用或为空返回 `null`。
String? readClipboardTextSync() {
  final List<List<String>> candidates = switch (Platform.operatingSystem) {
    'macos' => const <List<String>>[
        <String>['pbpaste'],
      ],
    'windows' => const <List<String>>[
        <String>[
          'powershell',
          '-NoProfile',
          '-Command',
          'Get-Clipboard -Raw',
        ],
      ],
    _ => const <List<String>>[
        <String>['wl-paste', '--no-newline'],
        <String>['xclip', '-selection', 'clipboard', '-o'],
        <String>['xsel', '--clipboard', '--output'],
      ],
  };
  for (final List<String> command in candidates) {
    try {
      final ProcessResult result = Process.runSync(
        command.first,
        command.skip(1).toList(),
      );
      if (result.exitCode != 0) continue;
      final String text = '${result.stdout}'.trim();
      if (text.isEmpty) continue;
      return text.length > kClipboardTextMaxChars
          ? text.substring(0, kClipboardTextMaxChars)
          : text;
    } on ProcessException {
      // 该平台的命令不存在：换下一个候选。
    }
  }
  return null;
}

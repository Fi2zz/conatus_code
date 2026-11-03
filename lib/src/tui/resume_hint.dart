/// 退出后的恢复提示：同步写控制终端，避免被 `exit()` 截断。
library;

import 'dart:io';

/// 恢复提示文本（不含前后换行）。
String resumeHintText(String sessionId) =>
    '恢复本次会话：nava -r $sessionId';

/// 把恢复提示写到 [ttyPath]；没有控制终端时回退 [fallback]（缺省 stdout）。
///
/// 用同步写而不是普通 stdout：nocterm 的 shutdown 会在 `stdout.flush()` 后
/// 立即 `exit()`，异步缓冲可能来不及落盘。
void writeResumeHint(
  String sessionId, {
  String ttyPath = '/dev/tty',
  StringSink? fallback,
}) {
  final String text = '\n${resumeHintText(sessionId)}\n';
  try {
    final File tty = File(ttyPath);
    if (tty.existsSync()) {
      tty.writeAsStringSync(text);
      return;
    }
  } on FileSystemException {
    // 没有控制终端时回退。
  }
  (fallback ?? stdout).write(text);
}

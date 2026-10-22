/// `.opencode` 命令级兜底：字面识别「路径段 + 写类操作符」。
///
/// **这只是 best-effort**，不是安全边界。真正的边界是 Seatbelt
/// （`deny file-write*`，见 `seatbelt_profile.dart` / `sandbox_assembly.dart`）。
/// 本检查覆盖沙箱未启用（`danger_full_access` / 后端不可用之外的本地直执）
/// 时命令工具那条路径上能被字面识别的写法；变量拼接、`sh -c "$CMD"`、读脚本
/// 再执行、`eval` 等都能绕过。
///
/// 保守取舍：宁可误拒（例如 `cat .opencode/x > out.txt` 也被拒），也不放过
/// 明显的写入形态。
library;

/// 错误码（与 fs 闸门的 `FsErrorCode.permissionDenied` 同一文案体系）。
const String kReadOnlyCommandCode = 'READ_ONLY_PATH';

/// 拒绝信息，与 `read_only_path_guard.dart` 的 `kReadOnlyPathMessage` 同文。
const String kReadOnlyCommandMessage = 'READ_ONLY_PATH: .opencode 目录只读';

/// 命令字面命中「`.opencode` 路径段 + 写类操作符」时返回拒绝信息，否则 null。
String? readOnlyCommandViolation(String command) {
  if (!_mentionsProtectedSegment(command)) return null;
  if (!_looksWrite(command)) return null;
  return kReadOnlyCommandMessage;
}

/// 去掉引号与反斜杠后，按「路径段边界」匹配 `.opencode`。
///
/// 覆盖 `.opencode/x`、`x/.opencode`、`>.opencode/x`、`--path=.opencode/x`
/// 等写法；`.opencode-backup`、`my.opencode.txt` 不算。
bool _mentionsProtectedSegment(String command) {
  final String flat = command.replaceAll(RegExp(r'''["'`\\]'''), ' ');
  return RegExp(
    r'(^|[\s=:;,()<>|&/])\.opencode($|[\s=:;,()<>|&/])',
  ).hasMatch(flat);
}

/// 写类操作符 / 命令：重定向、tee、rm、mv、cp、sed -i、truncate、touch……
final RegExp _writeOps = RegExp(
  r'(>>?|\btee\b|\brm\b|\bmv\b|\bcp\b|\bsed\s+-i|\btruncate\b|\btouch\b|'
  r'\bmkdir\b|\bln\b|\bchmod\b|\bdd\b|\binstall\b)',
);

bool _looksWrite(String command) => _writeOps.hasMatch(command);

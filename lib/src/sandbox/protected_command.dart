/// `.opencode` 命令级兜底：字面识别「路径段 + 写类操作符」。
///
/// **这只是 best-effort**，不是安全边界。真正的边界是 Seatbelt
/// （`deny file-write*`，见 `seatbelt_profile.dart` / `sandbox_assembly.dart`）。
/// 本检查覆盖沙箱未启用（`danger_full_access` / 后端不可用之外的本地直执）
/// 时命令工具那条路径上能被字面识别的写法；变量拼接、`sh -c "$CMD"`、读脚本
/// 再执行、`eval` 等都能绕过。
///
/// 覆盖两个目录：项目级 `.opencode` 与全局 `~/.config/opencode`
/// （`rm -rf ~/.config/opencode` 同样必须拒）。
///
/// 保守取舍：宁可误拒（例如 `cat .opencode/x > out.txt` 也被拒），也不放过
/// 明显的写入形态。
library;

import '../read_only_paths.dart';

/// 错误码（与 fs 闸门的 `FsErrorCode.permissionDenied` 同一文案体系）。
const String kReadOnlyCommandCode = kReadOnlyPathCode;

/// 拒绝信息，与 fs 闸门共用同一文案。
const String kReadOnlyCommandMessage = kReadOnlyPathMessage;

/// 命令字面命中「受保护目录 + 写类操作符」时返回拒绝信息，否则 null。
String? readOnlyCommandViolation(String command) {
  if (!_mentionsProtectedSegment(command)) return null;
  if (!_looksWrite(command)) return null;
  return kReadOnlyCommandMessage;
}

/// 去掉引号与反斜杠后按「路径段边界」匹配两个受保护目录。
///
/// 覆盖 `.opencode/x`、`x/.opencode`、`>.opencode/x`、`--path=.opencode/x`、
/// `~/.config/opencode`、`$HOME/.config/opencode` 等写法；
/// `.opencode-backup`、`my.opencode.txt` 不算。
bool _mentionsProtectedSegment(String command) {
  final String flat = command.replaceAll(RegExp(r'''["'`\\]'''), ' ');
  return _projectSegment.hasMatch(flat) || _globalSegment.hasMatch(flat);
}

/// 项目级 `.opencode` 段；大小写不敏感（APFS 上 `.OPENCODE` 是同一目录）。
final RegExp _projectSegment = RegExp(
  r'(^|[\s=:;,()<>|&/])\.opencode($|[\s=:;,()<>|&/])',
  caseSensitive: false,
);

/// 全局 `.../.config/opencode`（`~`、`$HOME` 或绝对路径拼写）。
final RegExp _globalSegment = RegExp(
  r'(^|[\s=:;,()<>|&/])\.config/opencode($|[\s=:;,()<>|&/])',
  caseSensitive: false,
);

/// 写类操作符 / 命令：重定向、tee、rm、mv、cp、sed -i、truncate、touch……
final RegExp _writeOps = RegExp(
  r'(>>?|\btee\b|\brm\b|\bmv\b|\bcp\b|\bsed\s+-i|\btruncate\b|\btouch\b|'
  r'\bmkdir\b|\bln\b|\bchmod\b|\bdd\b|\binstall\b)',
);

bool _looksWrite(String command) => _writeOps.hasMatch(command);

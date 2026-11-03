/// 目录 / 文件权限收紧：已经是目标模式时不再 fork `chmod`。
library;

import 'dart:io';

/// 目录 0700。
const int kPrivateDirMode = 0x1C0;

/// 文件 0600。
const int kPrivateFileMode = 0x180;

/// 把 [path] 收紧到 [mode]（八进制权限位掩码）。
///
/// 每个 `Process.runSync('chmod')` 都是一次 fork+exec（macOS 上 3–5ms），而项目
/// 注册表每次启动都要对 DB 文件与数据目录调一遍——实测十几毫秒都在这里。目标
/// 模式已经满足时直接返回。
void restrictPermissions(String path, int mode) {
  if (Platform.isWindows) return;
  final FileStat stat = FileStat.statSync(path);
  if (stat.type == FileSystemEntityType.notFound) return;
  if (stat.mode & 0xFFF == mode) return;
  try {
    Process.runSync('chmod', <String>[mode.toRadixString(8), path]);
  } on ProcessException {
    // 权限收紧失败不阻断启动（与既有行为一致）。
  }
}

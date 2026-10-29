/// Windows 下的 SQLite 动态库定位：优先使用与 nava 可执行文件同目录的
/// `sqlite3.dll`，其次是当前目录；都没有时交给 package:sqlite3 的默认回退
/// （`winsqlite3.dll`）。其他平台不做处理。
library;

import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

bool _configured = false;

/// 在打开数据库前调用；幂等。
void configureSqliteLibrary() {
  if (_configured || !Platform.isWindows) return;
  _configured = true;
  final String? path = findBundledSqlite();
  if (path == null) return;
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(path),
  );
}

/// 查找随二进制分发的 `sqlite3.dll`；找不到返回 `null`。
String? findBundledSqlite() {
  if (!Platform.isWindows) return null;
  final Set<String> dirs = <String>{
    File(Platform.resolvedExecutable).parent.path,
    Directory.current.path,
  };
  for (final String dir in dirs) {
    final String candidate = '$dir${Platform.pathSeparator}sqlite3.dll';
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

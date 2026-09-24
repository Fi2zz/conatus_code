/// 恢复最近会话：按 `<sessionDir>` 下规范会话文件的修改时间取最新。
library;

import 'dart:io';

import 'tui_options.dart';

/// 找 `<sessionDir>` 下最近修改的规范会话文件（`session_<uuid>.jsonl`）。
///
/// 只认 [isCanonicalSessionId] 格式的 id（其余是历史遗留 / 临时文件，不恢复）；
/// 目录不存在、为空或没有符合格式的文件时返回 `null`。
String? findRecentSessionId(String sessionDir) {
  final Directory dir = Directory(sessionDir);
  if (!dir.existsSync()) return null;
  String? best;
  DateTime? bestTime;
  for (final FileSystemEntity entity in dir.listSync()) {
    if (entity is! File) continue;
    final String name = entity.uri.pathSegments.last;
    if (!name.endsWith('.jsonl')) continue;
    final String id = name.substring(0, name.length - '.jsonl'.length);
    if (!isCanonicalSessionId(id)) continue;
    final DateTime time = entity.statSync().modified;
    if (best == null || time.isAfter(bestTime!)) {
      best = id;
      bestTime = time;
    }
  }
  return best;
}

/// 工作目录快照：轮询扫描的文件系统侧（与 StoryWatcher 的状态机分开）。
library;

import 'dart:io';

/// 扫描时跳过的目录（按 basename），与 GlobTool / ListFilesTool 对齐。
const Set<String> kStorySkipDirs = <String>{
  '.git',
  '.nava',
  '.conatus',
  'node_modules',
  '.dart_tool',
  'build',
};

/// 只跟踪这些文本扩展名（读回时再容错一次，双保险）。
const Set<String> kStoryTextExtensions = <String>{
  // 文档 / 配置
  '.md', '.txt', '.rst', '.adoc', '.csv',
  '.json', '.yaml', '.yml', '.toml', '.ini', '.cfg', '.conf', '.env',
  // 常见源码（编码智能体的主场景）
  '.dart', '.py', '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs',
  '.go', '.rs', '.java', '.kt', '.kts', '.scala', '.rb', '.php',
  '.cs', '.c', '.h', '.cc', '.cpp', '.hpp', '.swift', '.m', '.mm',
  '.sh', '.bash', '.zsh', '.ps1',
  '.html', '.htm', '.css', '.scss', '.less', '.vue', '.svelte',
  '.sql', '.xml', '.gradle',
};

/// 当前快照：相对路径（`/` 分隔）→ (mtime, 长度)。等长同毫秒的连续
/// 写入靠长度分辨；目录不可读时跳过该子树。
Future<Map<String, (DateTime, int)>> snapshotWorkdir(String dir) async {
  final Map<String, (DateTime, int)> out = <String, (DateTime, int)>{};
  await _walk(Directory(dir), '', out);
  return out;
}

Future<void> _walk(
  Directory current,
  String prefix,
  Map<String, (DateTime, int)> out,
) async {
  final List<FileSystemEntity> entries;
  try {
    entries = await current.list().toList();
  } catch (_) {
    return;
  }
  for (final FileSystemEntity entity in entries) {
    await _collect(entity, prefix, out);
  }
}

Future<void> _collect(
  FileSystemEntity entity,
  String prefix,
  Map<String, (DateTime, int)> out,
) async {
  final String name = entity.uri.pathSegments.lastWhere(
    (String s) => s.isNotEmpty,
    orElse: () => '',
  );
  if (entity is Directory) {
    if (!kStorySkipDirs.contains(name)) {
      await _walk(entity, '$prefix$name/', out);
    }
    return;
  }
  if (entity is! File) return;
  await _collectFile(entity, '$prefix$name', name, out);
}

Future<void> _collectFile(
  File file,
  String path,
  String name,
  Map<String, (DateTime, int)> out,
) async {
  final int dot = name.lastIndexOf('.');
  if (dot < 0 || !kStoryTextExtensions.contains(name.substring(dot))) return;
  try {
    out[path] = (await file.lastModified(), await file.length());
  } catch (_) {
    // 扫描窗口内被删的文件：跳过，删除语义 v1 不记。
  }
}

/// Agent 测试共用辅助：写 Agent 文件与只读快照。
library;

import 'dart:io';

/// 在 [root] 下写入相对路径为 [name] 的 Agent 文件。
void writeAgent(
  Directory root,
  String name, {
  String frontmatter = '',
  String body = 'body',
}) {
  final File file = File('${root.path}/$name');
  file.parent.createSync(recursive: true);
  final String header = frontmatter.trim().isEmpty
      ? ''
      : '---\n${frontmatter.trim()}\n---\n';
  file.writeAsStringSync('$header$body');
}

/// 目录内相对路径 + 内容的稳定快照（只读遍历）。
List<String> snapshotDirectory(Directory root) {
  final List<String> entries = <String>[
    for (final FileSystemEntity entity in root.listSync(
      recursive: true,
      followLinks: false,
    ))
      if (entity is File)
        '${entity.path.substring(root.path.length)}:${entity.readAsStringSync()}',
  ]..sort();
  return entries;
}

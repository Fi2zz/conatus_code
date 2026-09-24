/// checkpoint 的路径工具：相对路径、排除判定、复制落盘。
///
/// 快照/恢复都走 dart:io 直连（应用级信任域，不经 `'fs'` 接缝）。
library;

import 'dart:io';

/// 实体相对 [root] 的相对路径（分隔符规范化）。
String checkpointRelativeTo(FileSystemEntity entity, String root) {
  final List<String> rootSegs = checkpointPathSegments(root);
  final List<String> entitySegs = entity.uri.pathSegments;
  return entitySegs.sublist(rootSegs.length).join(Platform.pathSeparator);
}

/// 把路径拆成非空段（绝对/相对都行；去尾部斜杠）。
List<String> checkpointPathSegments(String path) {
  final String normalized = path.replaceAll(RegExp(r'[/\\]+$'), '');
  return normalized
      .split(Platform.pathSeparator)
      .where((String segment) => segment.isNotEmpty)
      .toList();
}

/// 相对路径是否命中排除：`projectDir` 整树、`.git` 整树、[ignore] 前缀。
///
/// [projectDir] 必须是相对 [root] 的路径（调用方算好再传，见 store 的
/// `projectRel`）；绝对路径会永远匹配不上相对路径。
bool checkpointExcluded(String rel, String projectDir, List<String> ignore) {
  if (_under(rel, projectDir) || _under(rel, '.git')) {
    return true;
  }
  for (final String prefix in ignore) {
    if (_under(rel, prefix)) return true;
  }
  return false;
}

bool _under(String rel, String prefix) {
  final String p = prefix.replaceAll(RegExp(r'[/\\]+$'), '');
  return rel == p || rel.startsWith('$p${Platform.pathSeparator}');
}

/// 把 [src] 复制到 `root/rel`（父目录自动建），返回目标文件。
Future<File> checkpointCopyInto(String src, String root, String rel) async {
  final File dst = File('$root${Platform.pathSeparator}$rel');
  dst.parent.createSync(recursive: true);
  await File(src).copy(dst.path);
  return dst;
}

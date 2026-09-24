/// checkpoint 的路径工具：相对路径、排除判定、gzip 压缩存取。
///
/// 快照/恢复都走 dart:io 直连（应用级信任域，不经 `'fs'` 接缝）。**存储一律
/// gzip 压缩**（`dart:io` 内置 `GZipCodec`，零额外依赖）：内容不以明文落盘，
/// 读时自动回退旧的明文文件（兼容升级前的检查点）。
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

/// 把 [bytes] 以 gzip 写入 `dir/rel.gz`（父目录自动建，flush 落盘）。
Future<void> checkpointWriteGz(List<int> bytes, String dir, String rel) async {
  final File target = File('$dir${Platform.pathSeparator}$rel.gz');
  target.parent.createSync(recursive: true);
  await target.writeAsBytes(gzip.encode(bytes), flush: true);
}

/// 读 `dir/rel.gz` 解压；`.gz` 不存在时回退明文 `dir/rel`（旧检查点）。
Future<List<int>> checkpointReadGz(String dir, String rel) async {
  final File gz = File('$dir${Platform.pathSeparator}$rel.gz');
  if (gz.existsSync()) return gzip.decode(await gz.readAsBytes());
  return File('$dir${Platform.pathSeparator}$rel').readAsBytes();
}

/// 从检查点目录恢复一个文件到 `root/rel`：读 gz（或明文回退）解压后写回，
/// 父目录自动建。返回目标文件。
Future<File> checkpointRestoreFromGz(
  String srcDir,
  String root,
  String rel,
) async {
  final List<int> bytes = await checkpointReadGz(srcDir, rel);
  final File dst = File('$root${Platform.pathSeparator}$rel');
  dst.parent.createSync(recursive: true);
  await dst.writeAsBytes(bytes, flush: true);
  return dst;
}


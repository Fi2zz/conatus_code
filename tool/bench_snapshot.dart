// 基线快照（turn 0）耗时基准：在真实工作区上跑一次全量基线，量耗时与归档大小。
//
// 基线是「打开会话」时最重的一步（大工作区可达数十秒），优化前后用它对比。
// 归档写到临时目录，不动真实 checkpoints；`.conatus/` 整树照常排除。
//
// 用法：dart run tool/bench_snapshot.dart <workspaceDir>
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';

Future<void> main(List<String> args) async {
  final String root = args.isEmpty ? Directory.current.path : args.first;
  final String sep = Platform.pathSeparator;
  final Directory projectDir = Directory('$root$sep.conatus')
    ..createSync(recursive: true);
  final Directory scratch = Directory.systemTemp.createTempSync('nava-bench');

  final (int files, int bytes) = await _measure(root, sep);
  stdout.writeln('工作区：$root');
  stdout.writeln('文件数：$files  总量：${(bytes / 1048576).toStringAsFixed(1)}MB');

  final File target = File('${scratch.path}${sep}bench.cp');
  final ArchiveCheckpointStore store = ArchiveCheckpointStore(
    root: root,
    projectDir: projectDir.path,
    keep: 0,
  );
  final Stopwatch watch = Stopwatch()..start();
  await store.snapshotUnindexed(target, 'bench', 0);
  watch.stop();

  stdout.writeln('turn 0 基线耗时：${watch.elapsedMilliseconds}ms');
  stdout.writeln(
    '归档大小：${(target.lengthSync() / 1048576).toStringAsFixed(1)}MB',
  );
  scratch.deleteSync(recursive: true);
}

/// 数一遍会被快照的文件数与总字节（排除项与 store 一致：`.conatus/` 整树）。
Future<(int, int)> _measure(String root, String sep) async {
  int files = 0;
  int bytes = 0;
  await for (final FileSystemEntity entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (entity.path.substring(root.length + 1).startsWith('.conatus$sep')) {
      continue;
    }
    files++;
    bytes += entity.lengthSync();
  }
  return (files, bytes);
}

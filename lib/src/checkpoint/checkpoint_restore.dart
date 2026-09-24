/// 检查点恢复：目标检查点 = base 全量铺底 +（差量时）changed 覆盖 / deleted
/// 删除 + 删当前多余文件（rsync 语义）。
library;

import 'dart:io';

import 'checkpoint_paths.dart';
import 'checkpoint_store.dart';
import 'checkpoint_types.dart';

/// 把工作区恢复到 [turn] 轮的文件状态。
///
/// [turn] 为 base（0）：复制 base 全量文件；为差量：先铺 base 全量，再覆盖
/// changed、删除 deleted。两种情况最后都删除「当前存在但目标状态没有」的文件
/// （排除项不受影响）。返回恢复计数。
Future<CheckpointRestore> restoreCheckpoint(
  CheckpointStore store,
  String sessionId,
  int turn,
) async {
  final Directory dir = store.directoryOf(sessionId, turn);
  if (!dir.existsSync()) {
    throw CheckpointException(
      'missing-checkpoint',
      '检查点 $turn 不存在（会话 $sessionId）',
    );
  }
  final CheckpointManifest manifest = store.manifestOf(sessionId, turn);
  int restored = 0;
  int removed = 0;
  final Set<String> target;
  if (manifest.isDelta) {
    final CheckpointManifest base = store.manifestOf(sessionId, 0);
    final Directory baseDir = store.directoryOf(sessionId, 0);
    final Set<String> deleted = manifest.deleted.toSet();
    final Set<String> basePaths = <String>{
      for (final CheckpointFileEntry entry in base.files) entry.path,
    };
    target = <String>{
      ...basePaths.where((String p) => !deleted.contains(p)),
      ...manifest.changed,
    };
    for (final CheckpointFileEntry entry in base.files) {
      if (deleted.contains(entry.path)) continue;
      await checkpointCopyInto(
        '${baseDir.path}${Platform.pathSeparator}${entry.path}',
        store.root,
        entry.path,
      );
      restored++;
    }
    for (final String path in manifest.changed) {
      await checkpointCopyInto(
        '${dir.path}${Platform.pathSeparator}$path',
        store.root,
        path,
      );
      restored++;
    }
    for (final String path in manifest.deleted) {
      final File file = File('${store.root}${Platform.pathSeparator}$path');
      if (file.existsSync()) {
        file.deleteSync();
        removed++;
      }
    }
  } else {
    target = <String>{for (final CheckpointFileEntry entry in manifest.files) entry.path};
    for (final CheckpointFileEntry entry in manifest.files) {
      await checkpointCopyInto(
        '${dir.path}${Platform.pathSeparator}${entry.path}',
        store.root,
        entry.path,
      );
      restored++;
    }
  }
  final int extras = await _deleteExtras(store, target);
  return CheckpointRestore(restored: restored, deleted: removed + extras);
}

/// 删除当前工作区中「不在目标状态、且未被排除」的文件；返回删除数。
Future<int> _deleteExtras(CheckpointStore store, Set<String> target) async {
  final List<File> extras = <File>[];
  await for (final FileSystemEntity entity
      in Directory(store.root).list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final String rel = checkpointRelativeTo(entity, store.root);
    if (checkpointExcluded(rel, store.projectRel, store.ignore)) continue;
    if (target.contains(rel)) continue;
    extras.add(entity);
  }
  for (final File file in extras) {
    file.deleteSync();
  }
  return extras.length;
}

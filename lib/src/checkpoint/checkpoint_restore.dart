/// 检查点恢复：目标检查点 = base 全量铺底 +（差量时）changed 覆盖 / deleted
/// 删除 + 删当前多余文件（rsync 语义）。新格式读单文件归档，旧版目录树回退。
library;

import 'dart:io';

import 'checkpoint_archive.dart';
import 'checkpoint_paths.dart';
import 'checkpoint_store.dart';
import 'checkpoint_types.dart';

/// 把工作区恢复到 [turn] 轮的文件状态；返回恢复计数。
Future<CheckpointRestore> restoreCheckpoint(
  CheckpointStore store,
  String sessionId,
  int turn,
) async {
  final File archive = store.archiveFile(sessionId, turn);
  if (archive.existsSync()) {
    return _restoreArchive(store, sessionId, turn, archive);
  }
  return _restoreLegacy(store, sessionId, turn);
}

/// 新格式（单文件归档）恢复。
Future<CheckpointRestore> _restoreArchive(
  CheckpointStore store,
  String sessionId,
  int turn,
  File archive,
) async {
  final (CheckpointManifest manifest, List<CheckpointArchiveEntry> entries) =
      readCheckpointArchive(archive);
  int restored = 0;
  int removed = 0;
  final Set<String> target;
  if (manifest.isDelta) {
    final (CheckpointManifest base, Map<String, List<int>> baseEntries) =
        await _readBase(store, sessionId);
    final Set<String> deleted = manifest.deleted.toSet();
    final Set<String> basePaths =
        <String>{for (final CheckpointFileEntry entry in base.files) entry.path};
    target = <String>{
      ...basePaths.where((String p) => !deleted.contains(p)),
      ...manifest.changed,
    };
    for (final MapEntry<String, List<int>> entry in baseEntries.entries) {
      if (deleted.contains(entry.key)) continue;
      await _writeEntry(store.root, entry.key, entry.value);
      restored++;
    }
    for (final (String path, List<int> bytes) in entries) {
      await _writeEntry(store.root, path, bytes);
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
    for (final (String path, List<int> bytes) in entries) {
      await _writeEntry(store.root, path, bytes);
      restored++;
    }
  }
  final int extras = await _deleteExtras(store, target);
  return CheckpointRestore(restored: restored, deleted: removed + extras);
}

/// 读 base（turn 0）的清单与条目：新归档优先，旧版目录回退。
Future<(CheckpointManifest, Map<String, List<int>>)> _readBase(
  CheckpointStore store,
  String sessionId,
) async {
  final File archive = store.archiveFile(sessionId, 0);
  if (archive.existsSync()) {
    final (CheckpointManifest manifest, List<CheckpointArchiveEntry> entries) =
        readCheckpointArchive(archive);
    return (
      manifest,
      <String, List<int>>{for (final (String p, List<int> b) in entries) p: b},
    );
  }
  final Directory? dir = store.legacyDir(sessionId, 0);
  if (dir == null) {
    throw const CheckpointException('missing-base', '缺少 base 检查点（turn 0）');
  }
  final CheckpointManifest manifest = store.manifestOf(sessionId, 0);
  final Map<String, List<int>> entries = <String, List<int>>{};
  for (final CheckpointFileEntry entry in manifest.files) {
    entries[entry.path] = await checkpointReadGz(dir.path, entry.path);
  }
  return (manifest, entries);
}

/// 旧版目录树检查点恢复（逐文件 gz/明文回退）。
Future<CheckpointRestore> _restoreLegacy(
  CheckpointStore store,
  String sessionId,
  int turn,
) async {
  final Directory? dir = store.legacyDir(sessionId, turn);
  if (dir == null) {
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
    final Directory? baseDir = store.legacyDir(sessionId, 0);
    final Set<String> deleted = manifest.deleted.toSet();
    final Set<String> basePaths = <String>{
      for (final CheckpointFileEntry entry in base.files) entry.path,
    };
    target = <String>{
      ...basePaths.where((String p) => !deleted.contains(p)),
      ...manifest.changed,
    };
    if (baseDir != null) {
      for (final CheckpointFileEntry entry in base.files) {
        if (deleted.contains(entry.path)) continue;
        await checkpointRestoreFromGz(baseDir.path, store.root, entry.path);
        restored++;
      }
    }
    for (final String path in manifest.changed) {
      await checkpointRestoreFromGz(dir.path, store.root, path);
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
    target = <String>{
      for (final CheckpointFileEntry entry in manifest.files) entry.path
    };
    for (final CheckpointFileEntry entry in manifest.files) {
      await checkpointRestoreFromGz(dir.path, store.root, entry.path);
      restored++;
    }
  }
  final int extras = await _deleteExtras(store, target);
  return CheckpointRestore(restored: restored, deleted: removed + extras);
}

Future<void> _writeEntry(String root, String rel, List<int> bytes) async {
  final File dst = File('$root${Platform.pathSeparator}$rel');
  dst.parent.createSync(recursive: true);
  await dst.writeAsBytes(bytes, flush: true);
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

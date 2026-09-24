/// 工作区快照存储：每个检查点 = 单个 gzip 归档文件。
///
/// 布局：`<projectDir>/checkpoints/<sessionId>/<turn>.gz`（**一个文件，不保留
/// 目录结构**；内容压缩存储，非明文）。turn 0 全量 base + 各轮相对 base 差量
/// （base 只存变化/新增文件 + 清单里的 deleted）。base（turn 0）永不 prune，
/// prune 只裁差量、保留最近 `keep - 1` 个。旧版目录树检查点（`<turn>/`）读时
/// 兼容。恢复见 `checkpoint_restore.dart`，归档编解码见
/// `checkpoint_archive.dart`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'checkpoint_archive.dart';
import 'checkpoint_paths.dart';
import 'checkpoint_types.dart';

/// 工作区快照存储。
class CheckpointStore {
  CheckpointStore({
    required String root,
    required this.projectDir,
    this.keep = 5,
    this.ignore = const <String>[],
  }) : root = Directory(root).absolute.path;

  /// 工作区根（构造时归一化为绝对路径）。
  final String root;

  /// 项目数据目录（相对 [root]，缺省 `.conatus`）；连同其整树排除在快照外。
  final String projectDir;

  /// 回滚点数（含 base）；`<=0` 不限制。
  final int keep;

  /// 额外忽略的相对路径前缀。
  final List<String> ignore;

  /// 某检查点的归档文件（新格式）。
  File archiveFile(String sessionId, int turn) => File(
      '$projectDir${Platform.pathSeparator}checkpoints'
      '${Platform.pathSeparator}$sessionId${Platform.pathSeparator}$turn.gz');

  /// 某检查点的旧版目录（格式迁移前的检查点；不存在返回 `null`）。
  Directory? legacyDir(String sessionId, int turn) {
    final Directory dir = Directory(
        '$projectDir${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}$sessionId${Platform.pathSeparator}$turn');
    return dir.existsSync() ? dir : null;
  }

  /// 快照当前工作区为 [turn] 轮（turn 0 全量 base，其余相对 base 差量）。
  Future<void> snapshot(
    String sessionId,
    int turn, {
    String? lastEventId,
  }) async {
    final File target = archiveFile(sessionId, turn);
    if (turn == 0) {
      await _snapshotBase(sessionId, target, lastEventId);
    } else {
      await _snapshotDelta(sessionId, turn, target, lastEventId);
    }
    // 清掉同轮的旧版目录（格式迁移）。
    legacyDir(sessionId, turn)?.deleteSync(recursive: true);
    prune(sessionId);
  }

  Future<void> _snapshotBase(
    String sessionId,
    File target,
    String? lastEventId,
  ) async {
    final List<CheckpointFileEntry> entries = <CheckpointFileEntry>[];
    final List<CheckpointArchiveEntry> blobs = <CheckpointArchiveEntry>[];
    await for (final FileSystemEntity entity
        in Directory(root).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final String rel = checkpointRelativeTo(entity, root);
      if (checkpointExcluded(rel, projectRel, ignore)) continue;
      final FileStat stat = entity.statSync();
      final List<int> bytes = await entity.readAsBytes();
      blobs.add((rel, bytes));
      entries.add(CheckpointFileEntry(
        path: rel,
        mtimeMs: stat.modified.millisecondsSinceEpoch,
        size: stat.size,
        hash: _sha256(entity.path),
      ));
    }
    await writeCheckpointArchive(
      target,
      CheckpointManifest(
        kind: 'base',
        turn: 0,
        lastEventId: lastEventId,
        files: entries,
      ),
      blobs,
    );
  }

  Future<void> _snapshotDelta(
    String sessionId,
    int turn,
    File target,
    String? lastEventId,
  ) async {
    final CheckpointManifest base = manifestOf(sessionId, 0);
    final Map<String, CheckpointFileEntry> baseStats =
        <String, CheckpointFileEntry>{
      for (final CheckpointFileEntry entry in base.files) entry.path: entry,
    };
    final List<String> changed = <String>[];
    final List<CheckpointArchiveEntry> blobs = <CheckpointArchiveEntry>[];
    final Set<String> current = <String>{};
    await for (final FileSystemEntity entity
        in Directory(root).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final String rel = checkpointRelativeTo(entity, root);
      if (checkpointExcluded(rel, projectRel, ignore)) continue;
      current.add(rel);
      final FileStat stat = entity.statSync();
      final CheckpointFileEntry? old = baseStats[rel];
      final bool statChanged = old == null ||
          old.size != stat.size ||
          old.mtimeMs != stat.modified.millisecondsSinceEpoch;
      final bool contentChanged = old != null &&
          !statChanged &&
          (old.hash == null || old.hash != _sha256(entity.path));
      if (statChanged || contentChanged) {
        blobs.add((rel, await entity.readAsBytes()));
        changed.add(rel);
      }
    }
    final List<String> deleted = <String>[
      for (final String path in baseStats.keys)
        if (!current.contains(path)) path,
    ];
    await writeCheckpointArchive(
      target,
      CheckpointManifest(
        kind: 'delta',
        turn: turn,
        lastEventId: lastEventId,
        changed: changed,
        deleted: deleted,
      ),
      blobs,
    );
  }

  /// 读某检查点的清单（新归档头部；旧版目录清单自动回退）；缺失抛异常。
  CheckpointManifest manifestOf(String sessionId, int turn) {
    final File archive = archiveFile(sessionId, turn);
    if (archive.existsSync()) {
      return readCheckpointArchive(archive).$1;
    }
    final Directory? legacy = legacyDir(sessionId, turn);
    if (legacy != null) {
      final File gz =
          File('${legacy.path}${Platform.pathSeparator}manifest.json.gz');
      final File plain =
          File('${legacy.path}${Platform.pathSeparator}manifest.json');
      if (gz.existsSync() || plain.existsSync()) {
        final List<int> bytes = gz.existsSync()
            ? gzip.decode(gz.readAsBytesSync())
            : plain.readAsBytesSync();
        return CheckpointManifest.fromJson(
            jsonDecode(utf8.decode(bytes)) as Map<String, Object?>);
      }
    }
    throw CheckpointException('missing-manifest', '检查点 $turn 缺少清单');
  }

  /// 现有检查点的摘要（turn 升序 + 有效文件数）。
  List<CheckpointInfo> list(String sessionId) {
    final List<int> turns = turnsOf(sessionId);
    if (turns.isEmpty) return const <CheckpointInfo>[];
    final Set<String> basePaths = <String>{
      for (final CheckpointFileEntry entry in manifestOf(sessionId, 0).files)
        entry.path,
    };
    return <CheckpointInfo>[
      for (final int turn in turns)
        CheckpointInfo(
            turn: turn, files: _effectiveCount(basePaths, turn, sessionId)),
    ];
  }

  int _effectiveCount(Set<String> basePaths, int turn, String sessionId) {
    final CheckpointManifest manifest = manifestOf(sessionId, turn);
    if (!manifest.isDelta) return manifest.files.length;
    final Set<String> deleted = manifest.deleted.toSet();
    int count = basePaths.where((String p) => !deleted.contains(p)).length;
    count += manifest.changed.where((String p) => !basePaths.contains(p)).length;
    return count;
  }

  /// 现有检查点的轮次（升序；兼容旧版目录）。
  List<int> turnsOf(String sessionId) {
    final Directory dir = Directory('$projectDir${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}$sessionId');
    if (!dir.existsSync()) return const <int>[];
    final List<int> turns = <int>[];
    for (final FileSystemEntity entity in dir.listSync()) {
      final String name = entity.path.split(Platform.pathSeparator).last;
      final String stem = name.endsWith('.gz')
          ? name.substring(0, name.length - '.gz'.length)
          : name;
      final int? turn = int.tryParse(stem);
      if (turn != null) turns.add(turn);
    }
    turns.sort();
    return turns;
  }

  /// 保留 turn 0（base）+ 最近 `keep - 1` 个差量；[keep] 非正不裁剪。
  void prune(String sessionId) {
    if (keep <= 0) return;
    final List<int> deltas =
        turnsOf(sessionId).where((int turn) => turn > 0).toList();
    final int excess = deltas.length - (keep - 1);
    for (int index = 0; index < excess; index++) {
      _deleteTurn(sessionId, deltas[index]);
    }
  }

  void _deleteTurn(String sessionId, int turn) {
    final File archive = archiveFile(sessionId, turn);
    if (archive.existsSync()) archive.deleteSync();
    legacyDir(sessionId, turn)?.deleteSync(recursive: true);
  }

  /// `projectDir` 相对 [root] 的路径（排除按相对路径比较）。
  String get projectRel {
    final String sep = Platform.pathSeparator;
    final String absRoot = root.endsWith(sep) ? root : '$root$sep';
    if (projectDir.startsWith(absRoot)) {
      return projectDir.substring(absRoot.length);
    }
    return projectDir;
  }
}

/// 文件内容 SHA-256（十六进制小写）。
String _sha256(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

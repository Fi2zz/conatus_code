/// 工作区快照存储：每个检查点 = 单个不可读名的 gzip 归档文件。
///
/// 布局：`<projectDir>/checkpoints/<sessionId>/<sha256前16位>.gz`（文件名是
/// 确定性哈希，**不可读、不暴露轮次**；轮次只记录在归档头部与会话级 `index`
/// 里）+ `index`（gzip 小索引：turn → 有效文件数，`list`/`prune` 只读它）。
/// turn 0 全量 base + 各轮相对 base 差量；base 永不 prune，prune 只裁差量、
/// 保留最近 `keep - 1` 个。旧版目录树检查点（`<turn>/` 可读名）读时兼容，
/// 索引缺失时按旧格式重建。恢复见 `checkpoint_restore.dart`。
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

  /// 某会话的检查点目录。
  Directory sessionDir(String sessionId) => Directory(
    '$projectDir${Platform.pathSeparator}checkpoints'
    '${Platform.pathSeparator}$sessionId',
  );

  /// 清空某会话的全部检查点（重绑即新时间线：旧 base/差量一并移除，
  /// 避免「新 base + 旧 delta」合成从未存在过的混合状态）。
  Future<void> clearSession(String sessionId) async {
    final Directory dir = sessionDir(sessionId);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// 某检查点的归档文件（不可读哈希名）。
  File archiveFile(String sessionId, int turn) => File(
    '${sessionDir(sessionId).path}${Platform.pathSeparator}'
    '${checkpointArchiveName(sessionId, turn)}',
  );

  /// 会话检查点索引文件。
  File indexFile(String sessionId) =>
      File('${sessionDir(sessionId).path}${Platform.pathSeparator}index');

  /// 某检查点的旧版目录（格式迁移前；不存在返回 `null`）。
  Directory? legacyDir(String sessionId, int turn) {
    final Directory dir = Directory(
      '${sessionDir(sessionId).path}'
      '${Platform.pathSeparator}$turn',
    );
    return dir.existsSync() ? dir : null;
  }

  /// 快照当前工作区为 [turn] 轮（turn 0 全量 base，其余相对 base 差量）。
  Future<void> snapshot(
    String sessionId,
    int turn, {
    String? lastEventId,
  }) async {
    final File target = archiveFile(sessionId, turn);
    final CheckpointInfo? files;
    if (turn == 0) {
      files = await _snapshotBase(sessionId, target, lastEventId);
    } else {
      files = await _snapshotDelta(sessionId, turn, target, lastEventId);
    }
    // 清掉同轮的旧版目录（格式迁移）。
    legacyDir(sessionId, turn)?.deleteSync(recursive: true);
    _upsertIndex(sessionId, files);
    prune(sessionId);
  }

  Future<CheckpointInfo> _snapshotBase(
    String sessionId,
    File target,
    String? lastEventId,
  ) async {
    // 两遍式：pass 1 收集清单（stat + 流式哈希），pass 2 按清单把内容流式
    // 写进归档——内存 O(chunk)。清单先行是容器格式约束。
    final List<CheckpointFileEntry> entries = await _scanEntries();
    final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
      target,
      CheckpointManifest(
        kind: 'base',
        turn: 0,
        lastEventId: lastEventId,
        files: entries,
      ),
    );
    await for (final FileSystemEntity entity in _walk()) {
      await writer.addFile(checkpointRelativeTo(entity, root), entity as File);
    }
    await writer.close();
    return CheckpointInfo(turn: 0, files: entries.length);
  }

  Future<CheckpointInfo> _snapshotDelta(
    String sessionId,
    int turn,
    File target,
    String? lastEventId,
  ) async {
    final CheckpointManifest base = await loadManifest(sessionId, 0);
    final Map<String, CheckpointFileEntry> baseStats =
        <String, CheckpointFileEntry>{
          for (final CheckpointFileEntry entry in base.files) entry.path: entry,
        };
    // pass 1：walk 分类（stat 变化直接记 changed；stat 未变的流式哈希兜底
    // 「mtime+size 同内容变」），得到完整 changed/deleted 才能写清单头。
    final List<String> changed = <String>[];
    final Set<String> current = <String>{};
    await for (final FileSystemEntity entity in _walk()) {
      final String rel = checkpointRelativeTo(entity, root);
      current.add(rel);
      final FileStat stat = entity.statSync();
      final CheckpointFileEntry? old = baseStats[rel];
      final bool statChanged =
          old == null ||
          old.size != stat.size ||
          old.mtimeMs != stat.modified.millisecondsSinceEpoch;
      if (statChanged) {
        changed.add(rel);
        continue;
      }
      final bool contentChanged =
          old.hash == null || old.hash != await _sha256File(entity as File);
      if (contentChanged) changed.add(rel);
    }
    final List<String> deleted = <String>[
      for (final String path in baseStats.keys)
        if (!current.contains(path)) path,
    ];
    // pass 2：把 changed 文件流式写进归档。
    final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
      target,
      CheckpointManifest(
        kind: 'delta',
        turn: turn,
        lastEventId: lastEventId,
        changed: changed,
        deleted: deleted,
      ),
    );
    for (final String rel in changed) {
      await writer.addFile(rel, File('$root${Platform.pathSeparator}$rel'));
    }
    await writer.close();
    final Set<String> basePaths = baseStats.keys.toSet();
    final Set<String> deletedSet = deleted.toSet();
    final int files =
        basePaths.where((String p) => !deletedSet.contains(p)).length +
        changed.where((String p) => !basePaths.contains(p)).length;
    return CheckpointInfo(turn: turn, files: files);
  }

  /// 流式列出工作区内需快照的文件（排除目录树、跟随链接关闭）。
  Stream<FileSystemEntity> _walk() => Directory(
    root,
  ).list(recursive: true, followLinks: false).where(_included);

  bool _included(FileSystemEntity entity) {
    if (entity is! File) return false;
    final String rel = checkpointRelativeTo(entity, root);
    return !checkpointExcluded(rel, projectRel, ignore);
  }

  /// pass 1 用：全部条目的 stat + 流式 SHA-256。
  Future<List<CheckpointFileEntry>> _scanEntries() async {
    final List<CheckpointFileEntry> entries = <CheckpointFileEntry>[];
    await for (final FileSystemEntity entity in _walk()) {
      final FileStat stat = entity.statSync();
      entries.add(
        CheckpointFileEntry(
          path: checkpointRelativeTo(entity, root),
          mtimeMs: stat.modified.millisecondsSinceEpoch,
          size: stat.size,
          hash: await _sha256File(entity as File),
        ),
      );
    }
    return entries;
  }

  /// 读某检查点的清单（新归档头部；旧版目录清单自动回退）；缺失抛异常。
  ///
  /// 同步版本：新归档会**整包解压**取头——大归档场景请用 [loadManifest]
  /// （流式只读头部）。保留给旧版目录与索引重建等同步路径。
  CheckpointManifest manifestOf(String sessionId, int turn) {
    final File archive = archiveFile(sessionId, turn);
    if (archive.existsSync()) {
      return readCheckpointArchive(archive).$1;
    }
    final Directory? legacy = legacyDir(sessionId, turn);
    if (legacy != null) {
      final File gz = File(
        '${legacy.path}${Platform.pathSeparator}manifest.json.gz',
      );
      final File plain = File(
        '${legacy.path}${Platform.pathSeparator}manifest.json',
      );
      if (gz.existsSync() || plain.existsSync()) {
        final List<int> bytes = gz.existsSync()
            ? gzip.decode(gz.readAsBytesSync())
            : plain.readAsBytesSync();
        return CheckpointManifest.fromJson(
          jsonDecode(utf8.decode(bytes)) as Map<String, Object?>,
        );
      }
    }
    throw CheckpointException('missing-manifest', '检查点 $turn 缺少清单');
  }

  /// 异步读清单：新归档走流式头部读取（不整包解压），旧版目录回退 [manifestOf]。
  Future<CheckpointManifest> loadManifest(String sessionId, int turn) async {
    final File archive = archiveFile(sessionId, turn);
    if (archive.existsSync()) {
      return readCheckpointManifest(archive);
    }
    return manifestOf(sessionId, turn);
  }

  /// 现有检查点的摘要（turn 升序 + 有效文件数；索引缺失时按目录重建）。
  List<CheckpointInfo> list(String sessionId) {
    final List<CheckpointInfo>? cached = readCheckpointIndex(
      indexFile(sessionId),
    );
    if (cached != null) return cached;
    return _rebuildIndex(sessionId);
  }

  /// 现有检查点的轮次（升序）。
  List<int> turnsOf(String sessionId) => <int>[
    for (final CheckpointInfo info in list(sessionId)) info.turn,
  ];

  /// 保留 turn 0（base）+ 最近 `keep - 1` 个差量；[keep] 非正不裁剪。
  void prune(String sessionId) {
    if (keep <= 0) return;
    final List<CheckpointInfo> infos = list(sessionId);
    final List<CheckpointInfo> deltas = infos
        .where((CheckpointInfo i) => i.turn > 0)
        .toList();
    final int excess = deltas.length - (keep - 1);
    if (excess <= 0) return;
    for (int index = 0; index < excess; index++) {
      _deleteTurn(sessionId, deltas[index].turn);
    }
    writeCheckpointIndex(indexFile(sessionId), <CheckpointInfo>[
      ...infos.where((CheckpointInfo i) => i.turn == 0),
      ...deltas.sublist(excess),
    ]);
  }

  void _upsertIndex(String sessionId, CheckpointInfo info) {
    final List<CheckpointInfo> infos = <CheckpointInfo>[
      ...list(sessionId).where((CheckpointInfo i) => i.turn != info.turn),
      info,
    ]..sort((CheckpointInfo a, CheckpointInfo b) => a.turn.compareTo(b.turn));
    writeCheckpointIndex(indexFile(sessionId), infos);
  }

  /// 索引缺失时重建：旧版可读目录 + 现有哈希归档头部。
  List<CheckpointInfo> _rebuildIndex(String sessionId) {
    final Directory dir = sessionDir(sessionId);
    if (!dir.existsSync()) return const <CheckpointInfo>[];
    final List<CheckpointInfo> infos = <CheckpointInfo>[];
    for (final FileSystemEntity entity in dir.listSync()) {
      final String name = entity.path.split(Platform.pathSeparator).last;
      if (name == 'index') continue;
      if (entity is Directory) {
        final int? turn = int.tryParse(name);
        if (turn == null) continue;
        final CheckpointManifest manifest = manifestOf(sessionId, turn);
        infos.add(
          CheckpointInfo(turn: turn, files: _countFor(sessionId, manifest)),
        );
      } else if (entity is File) {
        // 无扩展名的哈希归档：读头部拿轮次。
        final (CheckpointManifest manifest, _) = readCheckpointArchive(entity);
        infos.add(
          CheckpointInfo(
            turn: manifest.turn,
            files: _countFor(sessionId, manifest),
          ),
        );
      }
    }
    infos.sort(
      (CheckpointInfo a, CheckpointInfo b) => a.turn.compareTo(b.turn),
    );
    writeCheckpointIndex(indexFile(sessionId), infos);
    return infos;
  }

  int _countFor(String sessionId, CheckpointManifest manifest) {
    if (!manifest.isDelta) return manifest.files.length;
    final Set<String> basePaths = <String>{
      for (final CheckpointFileEntry entry in manifestOf(sessionId, 0).files)
        entry.path,
    };
    final Set<String> deleted = manifest.deleted.toSet();
    return basePaths.where((String p) => !deleted.contains(p)).length +
        manifest.changed.where((String p) => !basePaths.contains(p)).length;
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

/// 单文件 SHA-256（内存 ≈ 该文件自身；调用方逐文件调用，不累积）。
Future<String> _sha256File(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();

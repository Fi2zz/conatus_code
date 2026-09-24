/// 工作区文件快照存储：快照 / 恢复 / 保留 / 清单，dart:io 直连。
///
/// 快照与恢复都**不经 `'fs'` 接缝**（fs jail 是模型面的守卫；checkpoint 是应用
/// 级维护操作，与 recovery/sessions 同一信任域）。每个检查点是
/// `<projectDir>/checkpoints/<sessionId>/<turn>/` 下的一份完整文件复制 +
/// `manifest.json`。
///
/// 不用硬链接：模型经 `run_command` 原地写文件（`sed -i` 等）会共享 inode、
/// 把快照内容也改掉——只有原子写（rename）才有写时复制，无法保证。普通复制
/// 正确性优先。
library;

import 'dart:convert';
import 'dart:io';

import 'checkpoint_types.dart';

/// 工作区文件快照存储。
class CheckpointStore {
  CheckpointStore({
    required String root,
    required this.projectDir,
    this.keep = 5,
    this.ignore = const <String>[],
  }) : root = Directory(root).absolute.path;

  /// 工作区根（sandbox 根，构造时归一化为绝对路径）。
  final String root;

  /// 项目数据目录（相对 [root]，缺省 `.conatus`）；连同其整树排除在快照外。
  final String projectDir;

  /// 每会话保留的检查点数；`<=0` 不限制。
  final int keep;

  /// 额外忽略的相对路径前缀（如 `node_modules` / `build/`）。
  final List<String> ignore;

  Directory _dir(String sessionId, int turn) => Directory(
      '$projectDir${Platform.pathSeparator}checkpoints'
      '${Platform.pathSeparator}$sessionId${Platform.pathSeparator}$turn');

  /// 快照当前工作区为 [turn] 轮；写完后 prune 保留最近 [keep] 个。
  Future<void> snapshot(String sessionId, int turn) async {
    final Directory dir = _dir(sessionId, turn);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final List<String> files = <String>[];
    await for (final FileSystemEntity entity
        in Directory(root).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final String rel = _relativeTo(entity, root);
      if (_excluded(rel)) continue;
      final File target = File('${dir.path}${Platform.pathSeparator}$rel');
      target.parent.createSync(recursive: true);
      await entity.copy(target.path);
      files.add(rel);
    }
    File('${dir.path}${Platform.pathSeparator}manifest.json')
        .writeAsStringSync(jsonEncode(
      CheckpointManifest(turn: turn, files: files).toJson(),
    ));
    prune(sessionId);
  }

  /// 把工作区恢复到 [turn] 轮：清单文件覆盖回当前、当前多出的文件删除。
  Future<CheckpointRestore> restore(String sessionId, int turn) async {
    final Directory dir = _dir(sessionId, turn);
    if (!dir.existsSync()) {
      throw CheckpointException(
          'missing-checkpoint', '检查点 $turn 不存在（会话 $sessionId）');
    }
    final CheckpointManifest manifest = manifestOf(sessionId, turn);
    final Set<String> tracked = manifest.files.toSet();
    for (final String rel in manifest.files) {
      final File src = File('${dir.path}${Platform.pathSeparator}$rel');
      final File dst = File('$root${Platform.pathSeparator}$rel');
      dst.parent.createSync(recursive: true);
      await src.copy(dst.path);
    }
    final List<File> extra = <File>[];
    await for (final FileSystemEntity entity
        in Directory(root).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final String rel = _relativeTo(entity, root);
      if (_excluded(rel) || tracked.contains(rel)) continue;
      extra.add(entity);
    }
    for (final File file in extra) {
      file.deleteSync();
    }
    return CheckpointRestore(restored: manifest.files.length, deleted: extra.length);
  }

  /// 读某检查点的清单；清单缺失抛 [CheckpointException]。
  CheckpointManifest manifestOf(String sessionId, int turn) {
    final File file = File(
        '${_dir(sessionId, turn).path}${Platform.pathSeparator}manifest.json');
    if (!file.existsSync()) {
      throw CheckpointException('missing-manifest', '检查点 $turn 缺少清单');
    }
    final Object? json = jsonDecode(file.readAsStringSync());
    return CheckpointManifest.fromJson(json as Map<String, Object?>);
  }

  /// 现有检查点的轮次（升序）。
  List<int> list(String sessionId) {
    final Directory dir = Directory(
        '$projectDir${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}$sessionId');
    if (!dir.existsSync()) return const <int>[];
    final List<int> turns = <int>[];
    for (final FileSystemEntity entity in dir.listSync()) {
      if (entity is! Directory) continue;
      final String name = entity.path.split(Platform.pathSeparator).last;
      final int? turn = int.tryParse(name);
      if (turn != null) turns.add(turn);
    }
    turns.sort();
    return turns;
  }

  /// 保留最近 [keep] 个检查点；[keep] 非正时不裁剪。
  void prune(String sessionId) {
    if (keep <= 0) return;
    final List<int> turns = list(sessionId);
    final int excess = turns.length - keep;
    for (int index = 0; index < excess; index++) {
      _dir(sessionId, turns[index]).deleteSync(recursive: true);
    }
  }

  bool _excluded(String rel) {
    if (_under(rel, _projectRel) || _under(rel, '.git')) return true;
    for (final String prefix in ignore) {
      if (_under(rel, prefix)) return true;
    }
    return false;
  }

  /// `projectDir` 相对 [root] 的相对路径（排除项按相对路径比较）。
  String get _projectRel {
    final String sep = Platform.pathSeparator;
    final String absRoot = root.endsWith(sep) ? root : '$root$sep';
    if (projectDir.startsWith(absRoot)) {
      return projectDir.substring(absRoot.length);
    }
    return projectDir;
  }

  bool _under(String rel, String prefix) {
    final String p = prefix.replaceAll(RegExp(r'[/\\]+$'), '');
    return rel == p || rel.startsWith('$p${Platform.pathSeparator}');
  }

  static String _relativeTo(FileSystemEntity entity, String root) {
    final String normalized = root.replaceAll(RegExp(r'[/\\]+$'), '');
    final List<String> rootSegs =
        normalized.split(Platform.pathSeparator).where((String s) => s.isNotEmpty).toList();
    final List<String> entitySegs = entity.uri.pathSegments;
    return entitySegs.sublist(rootSegs.length).join(Platform.pathSeparator);
  }
}

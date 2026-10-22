/// `/diff` 的数据源：工作区 git 差异与检查点轮次差异。
///
/// 只读：不写工作区、不动检查点；无 git 或检查点缺失时返回空列表（工作区
/// 范围回落到轮次范围）。二进制与超大文件由 `diffLines` 降级为文件级结论。
library;

import 'dart:convert';

import '../checkpoint/checkpoint_changes.dart';
import '../checkpoint/checkpoint_manager.dart';
import '../checkpoint/checkpoint_types.dart';
import 'diff_model.dart';
import 'diff_parser.dart';
import 'working_diff.dart';

/// 按范围加载文件级差异。
class DiffSource {
  DiffSource({
    required this.workdir,
    required this.checkpoint,
    required this.sessionId,
    required this.turn,
  });

  /// 工作区根（绝对路径）。
  final String workdir;

  /// 检查点管理器（只走公开透传：`changesBetween` / `readFile` /
  /// `loadManifest`）。
  final CheckpointManager checkpoint;

  /// 会话 id。
  final String sessionId;

  /// 检查点轮次（`turn` 范围的目标轮）。
  final int turn;

  /// 加载 [scope] 范围内的差异（按路径排序）。
  Future<List<FileDiff>> load(DiffScope scope) async {
    if (scope == DiffScope.turn) return _turnDiff();
    final List<FileDiff>? working = await WorkingDiff(workdir).load();
    return working ?? _turnDiff();
  }

  /// 检查点轮次差异：目标轮 vs 上一轮；turn 0（或更早）与空比较。
  Future<List<FileDiff>> _turnDiff() async {
    try {
      final List<FileDiff> diffs = turn <= 0
          ? await _fromEmpty()
          : await _between(turn - 1, turn);
      return _sorted(<FileDiff>[
        for (final FileDiff diff in diffs)
          if (showsDiffPath(diff.path)) diff,
      ]);
    } on CheckpointException {
      return const <FileDiff>[];
    }
  }

  Future<List<FileDiff>> _fromEmpty() async {
    final int target = turn < 0 ? 0 : turn;
    final CheckpointManifest manifest = await checkpoint.loadManifest(
      sessionId,
      target,
    );
    final List<FileDiff> diffs = <FileDiff>[];
    for (final CheckpointFileEntry entry in manifest.files) {
      final String? after = await _read(target, entry.path);
      if (after == null) continue;
      diffs.addAll(diffLines(entry.path, null, after));
    }
    return diffs;
  }

  Future<List<FileDiff>> _between(int fromTurn, int toTurn) async {
    final List<CheckpointFileChange> changes = await checkpoint.changesBetween(
      sessionId,
      fromTurn,
      toTurn,
    );
    final List<FileDiff> diffs = <FileDiff>[];
    for (final CheckpointFileChange change in changes) {
      diffs.addAll(await _changeDiff(change, fromTurn, toTurn));
    }
    return diffs;
  }

  /// 两端内容都从检查点读；重命名保留状态词（存储只给新路径）。
  Future<List<FileDiff>> _changeDiff(
    CheckpointFileChange change,
    int fromTurn,
    int toTurn,
  ) async {
    final String? before = await _read(fromTurn, change.path);
    final String? after = await _read(toTurn, change.path);
    final List<FileDiff> diffs = diffLines(change.path, before, after);
    if (change.status != 'renamed') return diffs;
    return <FileDiff>[
      for (final FileDiff diff in diffs) diff.copyWith(status: 'renamed'),
    ];
  }

  Future<String?> _read(int atTurn, String path) async {
    final List<int>? bytes = await checkpoint.readFile(sessionId, atTurn, path);
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  List<FileDiff> _sorted(List<FileDiff> diffs) =>
      diffs..sort((FileDiff a, FileDiff b) => a.path.compareTo(b.path));
}

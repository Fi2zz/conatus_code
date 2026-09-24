/// checkpoint 的类型：清单、恢复计数与异常。
library;

/// 检查点相关错误。
class CheckpointException implements Exception {
  const CheckpointException(this.code, this.message);

  /// 机器可读错误码（`missing-manifest` / `missing-checkpoint`）。
  final String code;

  /// 人可读说明。
  final String message;

  @override
  String toString() => 'CheckpointException($code): $message';
}

/// 一个检查点的清单：轮次 + 被快照文件的相对路径列表 + 切点事件 id。
class CheckpointManifest {
  const CheckpointManifest({
    required this.turn,
    required this.files,
    this.lastEventId,
  });

  /// 反序列化。
  factory CheckpointManifest.fromJson(Map<String, Object?> json) =>
      CheckpointManifest(
        turn: json['turn'] as int? ?? 0,
        files: <String>[
          for (final Object? item
              in (json['files'] as List<Object?>?) ?? const <Object?>[])
            if (item is String) item,
        ],
        lastEventId: json['lastEventId'] as String?,
      );

  /// 快照时的轮次。
  final int turn;

  /// 被快照文件的相对路径（相对工作区根）。
  final List<String> files;

  /// 快照时刻该会话的最后一条事件 id；对话回滚用它做 fork 切点。
  /// `null` 表示该轮之前没有任何会话事件（空会话的 turn 0）。
  final String? lastEventId;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'turn': turn,
        'files': files,
        if (lastEventId != null) 'lastEventId': lastEventId,
      };
}

/// 一次恢复的结果计数。
class CheckpointRestore {
  const CheckpointRestore({required this.restored, required this.deleted});

  /// 覆盖/补回的文件数。
  final int restored;

  /// 删除的（当前有、检查点没有的）文件数。
  final int deleted;
}

/// 一个可用检查点的摘要（`/rewind list` 展示用）。
class CheckpointInfo {
  const CheckpointInfo({required this.turn, required this.files});

  /// 轮次。
  final int turn;

  /// 该检查点快照的文件数。
  final int files;
}

/// 一次回滚的结果：目标轮次 + 恢复计数 + 对话切点事件 id。
class CheckpointRewindResult {
  const CheckpointRewindResult({
    required this.turn,
    required this.restore,
    this.lastEventId,
  });

  /// 实际回滚到的轮次。
  final int turn;

  /// 恢复计数。
  final CheckpointRestore restore;

  /// 目标检查点的 [CheckpointManifest.lastEventId]（对话 fork 切点）。
  final String? lastEventId;
}

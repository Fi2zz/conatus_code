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

/// 一个检查点的清单：轮次 + 被快照文件的相对路径列表。
class CheckpointManifest {
  const CheckpointManifest({required this.turn, required this.files});

  /// 反序列化。
  factory CheckpointManifest.fromJson(Map<String, Object?> json) =>
      CheckpointManifest(
        turn: json['turn'] as int? ?? 0,
        files: <String>[
          for (final Object? item
              in (json['files'] as List<Object?>?) ?? const <Object?>[])
            if (item is String) item,
        ],
      );

  /// 快照时的轮次。
  final int turn;

  /// 被快照文件的相对路径（相对工作区根）。
  final List<String> files;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'turn': turn,
        'files': files,
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

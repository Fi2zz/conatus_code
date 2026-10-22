/// `/diff` 的数据模型：范围枚举与带统计的文件级差异。
library;

import 'diff_types.dart';

/// `/diff` 的比较范围。
enum DiffScope {
  /// 工作区相对索引的改动（含未跟踪文件）。
  working,

  /// 检查点在某一轮相对上一轮的改动。
  turn,
}

/// 一个文件的差异：路径、状态、hunk 与增删行数。
///
/// 继承 [DiffFile]，因此可直接喂给 `applyDiffFile` 等既有纯函数；比父类多出
/// 状态词、统计与截断标记，供 `/diff` 视图直接渲染。
class FileDiff extends DiffFile {
  const FileDiff({
    required super.path,
    required this.status,
    required super.hunks,
    this.additions = 0,
    this.deletions = 0,
    this.truncated = false,
  });

  /// `added` / `modified` / `deleted` / `renamed` / `binary`。
  final String status;

  /// 新增行数。
  final int additions;

  /// 删除行数。
  final int deletions;

  /// 文件过大、只给文件级结论（无 hunk）。
  final bool truncated;

  /// 复制并覆盖给定字段；其余保持不变。
  FileDiff copyWith({
    String? status,
    List<DiffHunk>? hunks,
    int? additions,
    int? deletions,
    bool? truncated,
  }) => FileDiff(
    path: path,
    status: status ?? this.status,
    hunks: hunks ?? this.hunks,
    additions: additions ?? this.additions,
    deletions: deletions ?? this.deletions,
    truncated: truncated ?? this.truncated,
  );
}

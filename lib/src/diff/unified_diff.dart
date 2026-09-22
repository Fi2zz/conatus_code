/// 统一格式（unified）diff 的生成：按行 LCS，输出 `--- / +++` 头与 `@@` hunk。
library;

import 'diff_types.dart';

/// 参与 LCS 计算的单侧最大行数；超过则退化为整体替换。
const int kMaxDiffLines = 2000;

/// 生成统一格式 diff；两侧内容相同返回空串。
///
/// [path] 同时用于 `--- a/path` 与 `+++ b/path` 两个头。
String buildUnifiedDiff({
  required String oldText,
  required String newText,
  required String path,
  int context = 3,
}) {
  final List<String> oldLines = splitLines(oldText);
  final List<String> newLines = splitLines(newText);
  final List<DiffOp> ops = diffLines(oldLines, newLines);
  final List<(int, int)> groups = _changeGroups(ops, context);
  if (groups.isEmpty) return '';
  final StringBuffer out = StringBuffer()
    ..writeln('--- a/$path')
    ..writeln('+++ b/$path');
  for (final (int start, int end) in groups) {
    _writeHunk(out, ops, start, end);
  }
  return out.toString();
}

/// 按 `\n` 切行；尾部换行不产生空行，空文本返回空列表。
List<String> splitLines(String text) {
  if (text.isEmpty) return const <String>[];
  final String body =
      text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  return body.isEmpty ? const <String>[] : body.split('\n');
}

/// 行级差异：LCS 动态规划 + 回溯；超过 [kMaxDiffLines] 退化为整体替换。
// REASON: LCS 动态规划是既定算法实现，分支结构由 DP 转移本身决定。
List<DiffOp> diffLines(List<String> a, List<String> b) {
  final int n = a.length;
  final int m = b.length;
  if (n > kMaxDiffLines || m > kMaxDiffLines) {
    return <DiffOp>[
      for (final String line in a) DiffOp(DiffOpKind.delete, line),
      for (final String line in b) DiffOp(DiffOpKind.insert, line),
    ];
  }
  final List<List<int>> lcs =
      <List<int>>[for (int i = 0; i <= n; i++) List<int>.filled(m + 1, 0)];
  for (int i = n - 1; i >= 0; i--) {
    for (int j = m - 1; j >= 0; j--) {
      if (a[i] == b[j]) {
        lcs[i][j] = lcs[i + 1][j + 1] + 1;
      } else {
        final int down = lcs[i + 1][j];
        final int right = lcs[i][j + 1];
        lcs[i][j] = down > right ? down : right;
      }
    }
  }
  final List<DiffOp> ops = <DiffOp>[];
  int i = 0;
  int j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      ops.add(DiffOp(DiffOpKind.equal, a[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      ops.add(DiffOp(DiffOpKind.delete, a[i]));
      i++;
    } else {
      ops.add(DiffOp(DiffOpKind.insert, b[j]));
      j++;
    }
  }
  while (i < n) {
    ops.add(DiffOp(DiffOpKind.delete, a[i]));
    i++;
  }
  while (j < m) {
    ops.add(DiffOp(DiffOpKind.insert, b[j]));
    j++;
  }
  return ops;
}

/// 把变更行聚成 hunk 区间（含 [context] 行上下文，间隔不足 2×context 时合并）。
// REASON: 区间合并是既定算法逻辑，分支由边界条件决定。
List<(int, int)> _changeGroups(List<DiffOp> ops, int context) {
  final List<int> changeIdx = <int>[
    for (int i = 0; i < ops.length; i++)
      if (ops[i].kind != DiffOpKind.equal) i,
  ];
  if (changeIdx.isEmpty) return const <(int, int)>[];
  final List<(int, int)> groups = <(int, int)>[];
  int start = (changeIdx.first - context).clamp(0, ops.length);
  int prev = changeIdx.first;
  for (final int idx in changeIdx.skip(1)) {
    if (idx - prev > 2 * context) {
      groups.add((start, (prev + context + 1).clamp(0, ops.length)));
      start = (idx - context).clamp(0, ops.length);
    }
    prev = idx;
  }
  groups.add((start, (prev + context + 1).clamp(0, ops.length)));
  return groups;
}

void _writeHunk(StringBuffer out, List<DiffOp> ops, int start, int end) {
  final (int oldStart, int newStart) = _starts(ops, start);
  int oldCount = 0;
  int newCount = 0;
  for (int i = start; i < end; i++) {
    final DiffOpKind kind = ops[i].kind;
    if (kind != DiffOpKind.insert) oldCount++;
    if (kind != DiffOpKind.delete) newCount++;
  }
  out.writeln(
      '@@ -${_range(oldStart, oldCount)} +${_range(newStart, newCount)} @@');
  for (int i = start; i < end; i++) {
    final DiffOp op = ops[i];
    out.writeln('${_prefix(op.kind)}${op.text}');
  }
}

String _range(int start, int count) => count == 1 ? '$start' : '$start,$count';

String _prefix(DiffOpKind kind) => switch (kind) {
      DiffOpKind.equal => ' ',
      DiffOpKind.delete => '-',
      DiffOpKind.insert => '+',
    };

/// 计算 [start] 位置对应的旧 / 新文件行号（1 起）。
(int, int) _starts(List<DiffOp> ops, int start) {
  int oldLine = 1;
  int newLine = 1;
  for (int i = 0; i < start; i++) {
    final DiffOpKind kind = ops[i].kind;
    if (kind != DiffOpKind.insert) oldLine++;
    if (kind != DiffOpKind.delete) newLine++;
  }
  return (oldLine, newLine);
}

/// `/diff` 视图的展示模型与纯文案：行类型、文件状态词、空结果与降级摘要。
///
/// 与视图分开是为了让占位与降级规则可以单独推敲：`truncated`（文件过大）
/// 与 `binary` 一律只给文件级结论，不把空 hunk 渲染成看似正常的差异。
library;

import 'package:conatus_diff/conatus_diff.dart';

/// diff 面板中的一行及其着色类别。
enum TuiDiffLineKind { header, context, addition, deletion, note }

/// 一行待渲染的 diff 文本。
class TuiDiffLine {
  const TuiDiffLine(this.kind, this.text);

  /// 行类别（决定颜色）。
  final TuiDiffLineKind kind;

  /// 行文本（含 `+` / `-` / ` ` 前缀）。
  final String text;
}

const Map<String, String> _statusMarks = <String, String>{
  'added': '+',
  'deleted': '-',
  'renamed': '→',
  'binary': 'B',
  'modified': '~',
};

const Map<String, String> _statusLabels = <String, String>{
  'added': '新增',
  'deleted': '删除',
  'renamed': '重命名',
  'binary': '二进制',
  'modified': '修改',
};

/// 文件树里的状态符号（`+` / `-` / `~` / `→` / `B`）。
String diffStatusMark(String status) => _statusMarks[status] ?? '~';

/// 文件树 / 标题里的状态词。
String diffStatusLabel(String status) => _statusLabels[status] ?? '变更';

/// 比较范围的中文名（标题用）。
String diffScopeLabel(DiffScope scope) =>
    scope == DiffScope.working ? '工作区' : '本轮';

/// 空结果提示：说明当前范围没有差异，而不是留一块空白。
String diffEmptyMessage(DiffScope scope) => '${diffScopeLabel(scope)}没有可显示的差异。';

/// 把一个文件的差异摊平成可渲染行：hunk 头 + 内容行。
///
/// 超过大小预算（[FileDiff.truncated]）与二进制文件只给占位摘要，不渲染
/// 任何 hunk；[FileDiff.coarse] 内容完整，先标注粗粒度再照常展示。
List<TuiDiffLine> diffDisplayLines(FileDiff diff) {
  if (diff.truncated) {
    return const <TuiDiffLine>[
      TuiDiffLine(TuiDiffLineKind.note, '文件过大（已截断）：仅显示文件级差异，未读取内容。'),
    ];
  }
  if (diff.status == 'binary') {
    return const <TuiDiffLine>[
      TuiDiffLine(TuiDiffLineKind.note, '二进制文件：没有可显示的文本差异。'),
    ];
  }
  final List<TuiDiffLine> lines = <TuiDiffLine>[];
  if (diff.coarse) {
    lines.add(
      const TuiDiffLine(TuiDiffLineKind.note, '粗粒度差异：内容完整但非最小 hunk，增删计数为整段统计。'),
    );
  }
  for (final DiffHunk hunk in diff.hunks) {
    lines.add(TuiDiffLine(TuiDiffLineKind.header, _hunkHeader(hunk)));
    for (final String line in hunk.lines) {
      lines.add(_classify(line));
    }
  }
  if (lines.isEmpty) {
    lines.add(const TuiDiffLine(TuiDiffLineKind.note, '没有可显示的行级差异。'));
  }
  return lines;
}

String _hunkHeader(DiffHunk hunk) =>
    '@@ -${hunk.oldStart},${hunk.oldLines} +${hunk.newStart},${hunk.newLines} @@';

TuiDiffLine _classify(String line) {
  final String first = line.isEmpty ? ' ' : line.substring(0, 1);
  if (first == '+') {
    return TuiDiffLine(TuiDiffLineKind.addition, line);
  }
  if (first == '-') {
    return TuiDiffLine(TuiDiffLineKind.deletion, line);
  }
  if (first == '@') {
    return TuiDiffLine(TuiDiffLineKind.header, line);
  }
  return TuiDiffLine(TuiDiffLineKind.context, line);
}

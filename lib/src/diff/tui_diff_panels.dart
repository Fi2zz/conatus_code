/// `/diff` 视图的分块渲染件：标题、左侧文件树、右侧 diff 面板。
///
/// 只接收已摊平的数据与滚动控制器，不持有状态；当前文件 / 已读集合由
/// [TuiDiffView] 的 state 决定。
library;

import 'package:nocterm/nocterm.dart';

import 'diff_model.dart';
import 'tui_diff_parts.dart';

const Map<TuiDiffLineKind, Color> _lineColors = <TuiDiffLineKind, Color>{
  TuiDiffLineKind.header: Colors.brightCyan,
  TuiDiffLineKind.context: Colors.gray,
  TuiDiffLineKind.addition: Colors.brightGreen,
  TuiDiffLineKind.deletion: Colors.brightRed,
  TuiDiffLineKind.note: Colors.brightYellow,
};

/// 视图标题：范围、按键提示、已读计数与数据源降级说明。
class TuiDiffHeader extends StatelessComponent {
  const TuiDiffHeader({
    super.key,
    required this.scope,
    required this.reviewed,
    this.notice,
  });

  /// 当前比较范围。
  final DiffScope scope;

  /// 已标记的文件数。
  final int reviewed;

  /// 数据源降级说明；正常为 `null`。
  final String? notice;

  @override
  Component build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Component>[
        Row(
          children: <Component>[
            Text(
              '差异 · ${diffScopeLabel(scope)}',
              style: const TextStyle(
                color: Colors.brightBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text('已读 $reviewed', style: const TextStyle(color: Colors.gray)),
          ],
        ),
        const Text(
          'j/k 滚动 · n/p 文件 · d 切源 · m 标记 · q 关闭',
          style: TextStyle(color: Colors.gray),
        ),
        if (notice != null)
          Text(
            '提示：$notice',
            style: const TextStyle(color: Colors.brightYellow),
          ),
      ],
    );
  }
}

/// 左侧文件树：当前项高亮，已读打勾，行首给 `+` / `-` / `~` 状态。
class TuiDiffTreePane extends StatelessComponent {
  const TuiDiffTreePane({
    super.key,
    required this.diffs,
    required this.index,
    required this.reviewed,
    required this.controller,
  });

  /// 全部文件差异。
  final List<FileDiff> diffs;

  /// 当前文件下标。
  final int index;

  /// 已读路径集合。
  final Set<String> reviewed;

  /// 列表滚动控制器。
  final ScrollController controller;

  @override
  Component build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Component>[
        Text('文件 ${diffs.length}', style: const TextStyle(color: Colors.gray)),
        Expanded(
          child: ListView.builder(
            controller: controller,
            itemCount: diffs.length,
            itemBuilder: (BuildContext context, int index) =>
                _row(diffs[index], index),
          ),
        ),
      ],
    );
  }

  Component _row(FileDiff diff, int row) {
    final bool current = row == index;
    final String mark = reviewed.contains(diff.path) ? '✓' : ' ';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: current ? const Color.fromRGB(30, 40, 60) : null,
      child: Text(
        '${current ? '>' : ' '}$mark ${diffStatusMark(diff.status)} ${diff.path}',
        style: TextStyle(
          color: current ? Colors.brightWhite : Colors.white,
          fontWeight: current ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

/// 右侧 diff 面板：文件摘要 + 可滚动 hunk 内容。
class TuiDiffPane extends StatelessComponent {
  const TuiDiffPane({super.key, required this.diff, required this.controller});

  /// 当前文件的差异。
  final FileDiff diff;

  /// 内容滚动控制器。
  final ScrollController controller;

  @override
  Component build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Component>[
        Text(
          '${diff.path}  ${diffStatusLabel(diff.status)}  '
          '+${diff.additions} -${diff.deletions}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Component>[
                for (final TuiDiffLine line in diffDisplayLines(diff))
                  Text(
                    line.text,
                    style: TextStyle(color: _lineColors[line.kind]),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

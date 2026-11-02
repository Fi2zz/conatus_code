/// `@` 文件补全浮层：紧贴输入框上方，展示完整相对路径（对齐 OpenCode）。
library;

import 'package:nocterm/nocterm.dart';

import 'at_ref_index.dart';
import 'at_ref_menu.dart';
import 'theme/nava_theme.dart';

/// 文件补全视图；按键与过滤在 [AtRefMenu] / 根组件处理。
class AtRefMenuView extends StatelessComponent {
  const AtRefMenuView({
    super.key,
    required this.matches,
    required this.selected,
    this.maxVisible = 10,
  });

  /// 匹配到的候选。
  final List<AtRefCandidate> matches;

  /// 当前选中项下标。
  final int selected;

  /// 最多显示的行数；超出时围绕选中项滚动。
  final int maxVisible;

  @override
  Component build(BuildContext context) {
    final int start = _windowStart();
    final int end = start + maxVisible > matches.length
        ? matches.length
        : start + maxVisible;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: NavaTheme.palette.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          for (int i = start; i < end; i++) _row(matches[i], i == selected),
        ],
      ),
    );
  }

  int _windowStart() {
    if (matches.length <= maxVisible) return 0;
    final int half = maxVisible ~/ 2;
    final int start = selected - half;
    if (start < 0) return 0;
    final int maxStart = matches.length - maxVisible;
    return start > maxStart ? maxStart : start;
  }

  Component _row(AtRefCandidate candidate, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: isSelected ? NavaTheme.palette.selected : null,
      child: Text(
        candidate.path,
        style: TextStyle(
          color: isSelected
              ? NavaTheme.palette.selectedText
              : candidate.isDir
              ? NavaTheme.palette.highlight
              : NavaTheme.palette.text,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

/// 会话标签栏：一行展示全部标签、活跃标记与关闭提示。
///
/// 标签数量上限为 [kTabCap]，整行单行渲染并在超宽时省略，不会把布局撑开。
library;

import 'package:nocterm/nocterm.dart';

import '../tui/session_display.dart';
import '../tui/theme/nava_theme.dart';
import 'tab_manager.dart';

/// 会话标签栏。
class TabBar extends StatelessComponent {
  const TabBar({
    super.key,
    required this.tabs,
    required this.active,
    this.nextHint = 'ctrl+tab',
    this.closeHint = '<leader>w',
  });

  /// 标签列表。
  final List<SessionTab> tabs;

  /// 活跃标签下标。
  final int active;

  /// 切换标签的键位提示（来自 keymap，可被 `[keybinds]` 改写）。
  final String nextHint;

  /// 关闭标签的键位提示。
  final String closeHint;

  /// 标签展示名：标题为空时回退短会话 id。
  String _label(SessionTab tab) {
    final String title = tab.title.trim();
    return title.isEmpty ? shortSessionId(tab.sessionId) : title;
  }

  String _line() {
    final List<String> labels = <String>[];
    for (int index = 0; index < tabs.length; index++) {
      final String mark = index == active ? '▸' : ' ';
      labels.add('$mark${index + 1}:${_label(tabs[index])}');
    }
    final List<String> hints = <String>[
      if (tabs.length > 1 && nextHint.trim().isNotEmpty)
        '${nextHint.trim()} 切换',
      if (closeHint.trim().isNotEmpty) '${closeHint.trim()} 关闭',
    ];
    final String switchHint = hints.isEmpty ? '' : '  (${hints.join(' · ')})';
    final String hint = '[${tabs.length}/$kTabCap] +$switchHint';
    return '${labels.join(' │ ')}  $hint';
  }

  @override
  Component build(BuildContext context) {
    if (tabs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        border: BoxBorder(bottom: BorderSide(color: NavaTheme.palette.border)),
      ),
      child: Row(
        children: <Component>[
          Expanded(
            child: Text(
              _line(),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: NavaTheme.palette.muted,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

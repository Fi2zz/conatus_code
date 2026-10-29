/// 设置面板视图：标题 + 操作提示 + 分页条目 + 页码。
library;

import 'package:nocterm/nocterm.dart';

import 'settings_prompt.dart';
import 'theme/nava_theme.dart';

/// 全屏设置面板。
class SettingsView extends StatelessComponent {
  const SettingsView({super.key, required this.prompt});

  /// 面板状态。
  final SettingsPrompt prompt;

  @override
  Component build(BuildContext context) {
    final int start = (prompt.page - 1) * kSettingsPageSize;
    final List<SettingsItem> items = prompt.pageItems;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      decoration: BoxDecoration(
        border: BoxBorder(
          top: BorderSide(color: NavaTheme.palette.info),
          bottom: BorderSide(color: NavaTheme.palette.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          Text(
            'Settings',
            style: TextStyle(
              color: NavaTheme.palette.info,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '↑↓ 选择 · ←→ 翻页 · Enter 确认 · Esc 取消',
            style: TextStyle(color: NavaTheme.palette.muted),
          ),
          const SizedBox(height: 1),
          for (int at = 0; at < items.length; at++)
            _row(items[at], start + at == prompt.index),
          const SizedBox(height: 1),
          Text(
            'Page ${prompt.page}/${prompt.pageCount}',
            style: TextStyle(color: NavaTheme.palette.muted),
          ),
        ],
      ),
    );
  }

  Component _row(SettingsItem item, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: selected ? NavaTheme.palette.selected : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          Text(
            '${selected ? '›' : ' '} ${item.title}',
            style: TextStyle(
              color: selected
                  ? NavaTheme.palette.selectedText
                  : NavaTheme.palette.text,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '   ${item.description}',
            style: TextStyle(
              color: selected
                  ? NavaTheme.palette.selectedText
                  : NavaTheme.palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

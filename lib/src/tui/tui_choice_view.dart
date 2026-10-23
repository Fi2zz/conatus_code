/// 选项浮层视图：标题 + 按键提示 + 选项列表（选中项高亮，当前项带标记）。
///
/// 按键在根组件处理（见 `tui.dart`），本组件只渲染 [TuiChoiceRequest]。
library;

import 'package:nocterm/nocterm.dart';

import 'theme/nava_theme.dart';
import 'tui_choice.dart';

/// 选项浮层。
class TuiChoiceView extends StatelessComponent {
  const TuiChoiceView({
    super.key,
    required this.request,
    required this.selected,
  });

  /// 当前提问。
  final TuiChoiceRequest request;

  /// 当前选中下标。
  final int selected;

  @override
  Component build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        border: BoxBorder.all(color: NavaTheme.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          Text(
            request.title,
            style: TextStyle(
              color: NavaTheme.palette.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '↑↓ 选择 · Enter 确认 · Esc 取消',
            style: TextStyle(color: NavaTheme.palette.muted),
          ),
          const SizedBox(height: 1),
          for (int i = 0; i < request.choices.length; i++)
            _row(request.choices[i], i == selected),
        ],
      ),
    );
  }

  Component _row(TuiChoice choice, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: isSelected ? NavaTheme.palette.selected : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          Row(
            children: <Component>[
              Text(
                '${isSelected ? '>' : ' '} ${choice.label}',
                style: TextStyle(
                  color: isSelected
                      ? NavaTheme.palette.selectedText
                      : NavaTheme.palette.text,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (choice.current) ...<Component>[
                const Text(' '),
                Text(
                  '← 当前',
                  style: TextStyle(color: NavaTheme.palette.warning),
                ),
              ],
            ],
          ),
          if (choice.description.isNotEmpty)
            Text(
              '  ${choice.description}',
              style: TextStyle(color: NavaTheme.palette.muted),
            ),
        ],
      ),
    );
  }
}

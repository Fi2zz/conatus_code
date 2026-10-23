/// 权限模式选择浮层视图：三档模式与说明，当前模式标记 `← 当前`。
///
/// 按键在根组件处理（见 `tui.dart`），本组件只渲染 [TuiPermissionPrompt]。
library;

import 'package:nocterm/nocterm.dart';

import 'theme/nava_theme.dart';
import 'tui_permission.dart';
import 'tui_permission_prompt.dart';

/// 权限模式选择浮层。
class TuiPermissionView extends StatelessComponent {
  const TuiPermissionView({super.key, required this.prompt});

  /// 浮层状态。
  final TuiPermissionPrompt prompt;

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
            '权限模式（↑↓ 选择，Enter 切换，Esc 关闭）',
            style: TextStyle(
              color: NavaTheme.palette.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          for (final TuiPermissionMode mode in TuiPermissionMode.values)
            _row(mode),
        ],
      ),
    );
  }

  Component _row(TuiPermissionMode mode) {
    final bool isSelected = mode == prompt.selected;
    final bool isCurrent = mode == prompt.current;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: isSelected ? NavaTheme.palette.selected : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          Text(
            '${isSelected ? '>' : ' '} ${mode.label}'
            '${isCurrent ? '  ← 当前' : ''}',
            style: TextStyle(
              color: isSelected
                  ? NavaTheme.palette.selectedText
                  : NavaTheme.palette.text,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '   ${mode.description}',
            style: TextStyle(
              color: isSelected
                  ? NavaTheme.palette.text
                  : NavaTheme.palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

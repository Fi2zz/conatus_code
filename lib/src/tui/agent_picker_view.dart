/// Agent 选择面板视图：`↑↓` 选择、`Enter` 切换、`Esc` 关闭（按键在根组件处理）。
library;

import 'package:nocterm/nocterm.dart';

import '../agents/agent_definition.dart';
import '../agents/agent_picker.dart';
import 'theme/nava_theme.dart';

/// Agent 选择面板视图。
class AgentPickerView extends StatelessComponent {
  const AgentPickerView({super.key, required this.picker});

  /// 面板状态。
  final AgentPicker picker;

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
            'Agent（↑↓ 选择，Enter 切换，Esc 关闭）',
            style: TextStyle(
              color: NavaTheme.palette.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          if (picker.list.isEmpty)
            Text(
              '没有可用的 Agent。',
              style: TextStyle(color: NavaTheme.palette.muted),
            )
          else
            for (int at = 0; at < picker.list.length; at++)
              _row(picker.list[at], at == picker.index),
        ],
      ),
    );
  }

  Component _row(AgentDefinition agent, bool selected) {
    final bool usable = agent.mode != AgentMode.subagent;
    final String cursor = selected ? '>' : ' ';
    final String mark = agent.id == picker.currentId ? '*' : ' ';
    final String mode = switch (agent.mode) {
      AgentMode.primary => '',
      AgentMode.subagent => '  （仅子 Agent）',
      AgentMode.all => '  （主/子）',
    };
    final String description = agent.description.isEmpty
        ? mode
        : '  ${agent.description}$mode';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: selected ? NavaTheme.palette.selected : null,
      child: Text(
        '$cursor$mark ${agent.id}$description',
        style: TextStyle(
          color: usable
              ? (selected
                    ? NavaTheme.palette.selectedText
                    : NavaTheme.palette.text)
              : NavaTheme.palette.muted,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

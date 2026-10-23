/// Agent 选择面板与状态：列出可见 Agent，跳过仅可作子 Agent 的条目。
library;

import 'package:nocterm/nocterm.dart';

import 'agent_definition.dart';
import 'agent_registry.dart';

/// Agent 选择面板状态（`/agents` 打开）。
///
/// [list] 是注册表里全部可见 Agent（含 hidden 之外的全部）；`mode == subagent`
/// 的条目照常展示，但 [move] 跳过、[selectedAgent] 返回 `null`，由控制器提示
/// 「只能作为子 Agent」。hidden Agent 不进入列表。
class AgentPicker {
  /// 创建面板状态；[onChanged] 在状态变化时触发重绘。
  AgentPicker({required this.onChanged});

  /// 状态变化回调。
  final void Function() onChanged;

  /// 面板是否打开。
  bool open = false;

  /// 可见 Agent 列表（按 ID 排序）。
  List<AgentDefinition> list = const <AgentDefinition>[];

  /// 当前光标。
  int index = 0;

  /// 当前会话 Agent ID（渲染 `*` 标记）。
  String currentId = '';

  /// 打开面板并定位到当前 Agent。
  void show(AgentRegistry registry, {required String currentId}) {
    list = List<AgentDefinition>.of(registry.visible);
    this.currentId = currentId;
    index = _initialIndex(currentId);
    open = true;
    onChanged();
  }

  /// 关闭面板。
  void close() {
    open = false;
    onChanged();
  }

  /// 条目是否可作为主会话 Agent。
  bool selectableAt(int at) =>
      at >= 0 && at < list.length && list[at].mode != AgentMode.subagent;

  /// 光标所在的条目（可能是仅子 Agent 的条目）。
  AgentDefinition? get focused => list.isEmpty ? null : list[index];

  /// 当前选中的可选 Agent；仅子 Agent 条目返回 `null`。
  AgentDefinition? get selectedAgent {
    final AgentDefinition? agent = focused;
    return agent != null && agent.mode != AgentMode.subagent ? agent : null;
  }

  /// 移动光标（跳过仅子 Agent 条目；到边界即停）。
  void move(int delta) {
    if (delta == 0 || list.isEmpty) {
      return;
    }
    final int direction = delta > 0 ? 1 : -1;
    int next = index;
    for (int step = 0; step < list.length; step++) {
      next += direction;
      if (next < 0 || next >= list.length) {
        return;
      }
      if (!selectableAt(next)) {
        continue;
      }
      index = next;
      onChanged();
      return;
    }
  }

  int _initialIndex(String id) {
    final int current = list.indexWhere((AgentDefinition a) => a.id == id);
    if (current >= 0 && selectableAt(current)) {
      return current;
    }
    for (int at = 0; at < list.length; at++) {
      if (selectableAt(at)) {
        return at;
      }
    }
    return 0;
  }
}

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
        border: BoxBorder.all(color: Colors.brightBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          const Text(
            'Agent（↑↓ 选择，Enter 切换，Esc 关闭）',
            style: TextStyle(
              color: Colors.brightBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          if (picker.list.isEmpty)
            const Text('没有可用的 Agent。', style: TextStyle(color: Colors.gray))
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
      color: selected ? const Color.fromRGB(30, 40, 60) : null,
      child: Text(
        '$cursor$mark ${agent.id}$description',
        style: TextStyle(
          color: usable
              ? (selected ? Colors.brightWhite : Colors.white)
              : Colors.gray,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

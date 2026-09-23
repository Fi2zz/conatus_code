/// TUI 外框组件：顶栏、输入栏与状态栏。
library;

import 'dart:io';

import 'package:nocterm/nocterm.dart';

import 'tui_views.dart';

/// 顶栏：应用名 / 当前会话 / 模型。
class TuiHeader extends StatelessComponent {
  const TuiHeader({
    super.key,
    required this.name,
    required this.sessionId,
    required this.modelLabel,
  });

  /// 应用 / 场景名。
  final String name;

  /// 当前会话 id。
  final String sessionId;

  /// 模型标签。
  final String modelLabel;

  @override
  Component build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: const Color.fromRGB(0, 40, 80),
        border: BoxBorder.all(color: Colors.cyan),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Component>[
          Text(
            'Conatus TUI · $name',
            style: const TextStyle(
              color: Colors.brightWhite,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '会话：$sessionId',
            style: const TextStyle(color: Colors.yellow),
          ),
          Text(
            '模型：$modelLabel',
            style: const TextStyle(color: Colors.gray),
          ),
        ],
      ),
    );
  }
}

/// 输入栏：`> ` 前缀 + 单行输入框（思考中置灰只读，避免丢输入）。
///
/// 附件以占位标记（`[image #N (宽×高)]`）形式留在输入框文本里，随文本提交时
/// 提取（见 `tui_attachment.dart`），不再单独渲染附件行。
class TuiInputBar extends StatelessComponent {
  const TuiInputBar({
    super.key,
    required this.controller,
    required this.focused,
    required this.busy,
    required this.onSubmitted,
    this.onKeyEvent,
  });

  /// 文本控制器。
  final TextEditingController controller;

  /// 是否聚焦。
  final bool focused;

  /// 是否思考中。
  final bool busy;

  /// 提交回调。
  final ValueChanged<String> onSubmitted;

  /// 文本框按键拦截（返回 true 吞掉）：`/` 菜单打开时用于 ↑↓/Enter/Esc/Tab。
  final bool Function(KeyboardEvent event)? onKeyEvent;

  @override
  Component build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: const BoxDecoration(
        color: Color.fromRGB(20, 20, 40),
        border: BoxBorder(top: BorderSide(color: Colors.blue)),
      ),
      child: Row(
        children: <Component>[
          const Text('> ', style: TextStyle(color: Colors.green)),
          Expanded(
            child: TextField(
              key: ValueKey<bool>(busy),
              controller: controller,
              focused: focused,
              readOnly: busy,
              style: const TextStyle(color: Colors.white),
              placeholder: busy ? '思考中…' : '输入消息，/help 查看命令',
              onSubmitted: onSubmitted,
              onKeyEvent: onKeyEvent,
            ),
          ),
        ],
      ),
    );
  }
}

/// 状态栏：思考动画 / 操作提示 / 面板按键说明。
class TuiStatusBar extends StatelessComponent {
  const TuiStatusBar({
    super.key,
    required this.pickerOpen,
    required this.busy,
    required this.tick,
    this.menuOpen = false,
    this.choiceOpen = false,
    this.exitPending = false,
    this.permissionLabel = '',
    this.hasSelection = false,
  });

  /// 会话面板是否打开。
  final bool pickerOpen;

  /// 是否思考中。
  final bool busy;

  /// 动画帧计数。
  final int tick;

  /// `/` 命令菜单是否打开。
  final bool menuOpen;

  /// 选项浮层是否打开。
  final bool choiceOpen;

  /// Ctrl+C 退出确认是否挂起（等待再按一次）。
  final bool exitPending;

  /// 当前权限模式名；空则不显示。
  final String permissionLabel;

  /// 消息区是否有鼠标选区（提示可复制）。
  final bool hasSelection;

  @override
  Component build(BuildContext context) {
    final String hint;
    if (exitPending) {
      hint = '再按一次 Ctrl+C 退出';
    } else if (choiceOpen) {
      hint = '[↑↓] 选择 | [Enter] 确认 | [Esc] 取消';
    } else if (pickerOpen) {
      hint = '[↑↓] 选择会话 | [Enter] 切换 | [Esc] 关闭';
    } else if (menuOpen) {
      hint = '[↑↓] 选择命令 | [Enter] 运行 | [Tab] 补全 | [Esc] 关闭';
    } else if (busy) {
      hint = '${tuiSpinner(tick)} 思考中${tuiDots(tick)}';
    } else if (hasSelection) {
      hint = Platform.isMacOS
          ? '选中后 ⌥C（Option+C）/ Ctrl+C 复制 | /help 命令'
          : '选中后 Ctrl+C 复制 | /help 命令';
    } else {
      hint = '回车发送 | /help 命令 | /sessions 会话 | Ctrl+C 退出';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: const BoxDecoration(
        color: Color.fromRGB(0, 20, 40),
        border: BoxBorder(top: BorderSide(color: Colors.cyan)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Component>[
          Text(
            permissionLabel.isEmpty ? '' : '权限：$permissionLabel',
            style: const TextStyle(color: Colors.brightYellow),
          ),
          Text(
            hint,
            style: TextStyle(
              color: busy ? Colors.brightYellow : Colors.gray,
            ),
          ),
        ],
      ),
    );
  }
}

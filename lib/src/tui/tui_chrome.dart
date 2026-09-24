/// TUI 外框组件：顶栏、输入栏与状态栏。
library;

import 'dart:io';
import 'package:nocterm/nocterm.dart';
import 'tui_shell_mode.dart';
import 'tui_views.dart';

const borderSode = BorderSide(color: Colors.blue);

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
    this.shellMode = false,
    this.onKeyEvent,
  });

  /// shell 模式：前缀换成 `! `，占位提示改为 shell 提示。
  final bool shellMode;

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

  /// 占位提示：思考中 / shell 模式 / 普通输入。
  String _placeholder() {
    if (busy) return '思考中…';
    return shellMode ? shellInputPlaceholder() : '输入消息，/help 查看命令';
  }

  @override
  Component build(BuildContext context) {
    return Container(
      // padding: const EdgeInsets.symmetric(horizontal: 0),
      decoration: const BoxDecoration(
        // color: Color.fromRGB(20, 20, 40),
        border: BoxBorder(
          top: borderSode,
          bottom: borderSode,
          left: borderSode,
          right: borderSode,
        ),
        // border: BoxBorder(top: BorderSide(color: Colors.blue)),
      ),
      child: Row(
        children: <Component>[
          Text(
            shellMode ? '! ' : '> ',
            style: TextStyle(
              color: shellMode ? Colors.brightYellow : Colors.green,
            ),
          ),
          Expanded(
            child: TextField(
              key: ValueKey<bool>(busy),
              controller: controller,
              focused: focused,
              readOnly: busy,
              style: const TextStyle(color: Colors.white),
              placeholder: _placeholder(),
              onSubmitted: onSubmitted,
              onKeyEvent: onKeyEvent,
            ),
          ),
        ],
      ),
    );
  }
}

/// 状态栏：左（权限 + 模型）/ 中（操作提示）/ 右（目录 + 分支 + 上下文用量）。
class TuiStatusBar extends StatelessComponent {
  const TuiStatusBar({
    super.key,
    required this.pickerOpen,
    required this.busy,
    required this.tick,
    required this.modelLabel,
    this.shellMode = false,
    this.location = '',
    this.contextText = '',
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

  /// 当前模型标签（左段）。
  final String modelLabel;

  /// shell 模式：提示 shell 操作键。
  final bool shellMode;

  /// 工作目录 + git 分支（右段）；空则不显示。
  final String location;

  /// 上下文用量文本（右段）；空则不显示。
  final String contextText;

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
    if (shellMode) {
      hint = shellStatusHint();
    } else if (exitPending) {
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
          ? '已自动复制到系统剪贴板 | /help 命令'
          : '选中后 Ctrl+C 复制 | /help 命令';
    } else {
      hint = '回车发送 | /help 命令 | /sessions 会话 | Ctrl+C 退出';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      // decoration: const BoxDecoration(
      //   color: Color.fromRGB(0, 20, 40),
      //   border: BoxBorder(top: BorderSide(color: Colors.cyan)),
      // ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final String left = _leftText();
          final String right = _rightText();
          final int width = constraints.maxWidth.toInt();
          final int leftWidth = _displayWidth(left);
          // 窄终端先舍右段（环境信息），保住左段与中间操作提示。
          final bool showRight = leftWidth + _displayWidth(right) + 12 <= width;
          final int spare =
              width - leftWidth - (showRight ? _displayWidth(right) : 0);
          final bool showHint = spare >= 12;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Component>[
              Text(
                permissionLabel,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(color: Colors.brightYellow),
              ),
              const Spacer(),

              Expanded(
                child: showHint
                    ? Text(
                        hint,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: busy ? Colors.brightYellow : Colors.gray,
                        ),
                      )
                    : const SizedBox(),
              ),
              Text(
                showRight ? right : '',
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(color: Colors.gray),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 左段：权限模式 + 模型标签。
  String _leftText() {
    final String model = modelLabel;
    return permissionLabel.isEmpty
        ? model
        : '$permissionLabel   $model $location';
  }

  /// 右段：目录 + 分支 + 上下文用量。
  String _rightText() {
    final String context = contextText.isEmpty ? '' : ' · $contextText';
    return '$location$context';
  }

  /// 估算屏上宽度：CJK 全角按两列，其余按一列（近似）。
  int _displayWidth(String text) {
    int width = 0;
    for (final int code in text.codeUnits) {
      width += code >= 0x2E80 ? 2 : 1;
    }
    return width;
  }
}

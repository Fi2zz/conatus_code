/// TUI 外框组件：顶栏、输入栏与状态栏。
library;

import 'dart:io';
import 'package:nocterm/nocterm.dart';
import 'tui_shell_mode.dart';
import 'tui_views.dart';

const borderSode = BorderSide(color: Colors.blue);

/// shell 模式下的输入框边框（紫色，与普通模式的蓝色区分）。
const BorderSide kShellInputBorder = BorderSide(color: Colors.magenta);

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

  /// 输入框边框：shell 模式紫色（一眼区分当前在跑 shell），其余蓝色。
  BorderSide get _border =>
      shellMode ? kShellInputBorder : borderSode;

  @override
  Component build(BuildContext context) {
    return Container(
      // padding: const EdgeInsets.symmetric(horizontal: 0),
      decoration: BoxDecoration(
        // color: Color.fromRGB(20, 20, 40),
        border: BoxBorder(
          top: _border,
          bottom: _border,
          left: _border,
          right: _border,
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
/// 状态栏三段之间保留的最小空隙（列）。
const int _kSegmentGap = 2;

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      // decoration: const BoxDecoration(
      //   color: Color.fromRGB(0, 20, 40),
      //   border: BoxBorder(top: BorderSide(color: Colors.cyan)),
      // ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final String hint = _hint();
          final (bool showRight, bool showHint) = _fit(
            constraints.maxWidth.toInt(),
            _leftText(),
            hint,
            _rightText(),
          );
          return _bar(hint, showRight, showHint);
        },
      ),
    );
  }

  /// 中段提示：按当前状态取一条。
  String _hint() {
    if (shellMode) {
      return shellStatusHint();
    } else if (exitPending) {
      return '再按一次 Ctrl+C 退出';
    } else if (choiceOpen) {
      return '[↑↓] 选择 | [Enter] 确认 | [Esc] 取消';
    } else if (pickerOpen) {
      return '[↑↓] 选择会话 | [Enter] 切换 | [Esc] 关闭';
    } else if (menuOpen) {
      return '[↑↓] 选择命令 | [Enter] 运行 | [Tab] 补全 | [Esc] 关闭';
    } else if (busy) {
      return '${tuiSpinner(tick)} 思考中${tuiDots(tick)}';
    } else if (hasSelection) {
      return Platform.isMacOS
          ? '已自动复制到系统剪贴板 | /help 命令'
          : '选中后 Ctrl+C 复制 | /help 命令';
    }
    return '回车发送 | /help 命令 | /sessions 会话 | Ctrl+C 退出';
  }

  /// 按屏宽决定三段去留：返回 (是否显示右段, 是否显示中段提示)。
  ///
  /// 提示优先于右段环境信息；提示两侧各留 [_kSegmentGap] 列（其 `Padding` 宽度
  /// 已计入 [_kSegmentGap] * 2）。阈值按**实际显示宽度**判断，不用固定常数——
  /// 「再按一次 Ctrl+C 退出」有 20 列，按 12 列判断等于让它挤进放不下的空间
  /// 再被裁掉半截。
  (bool, bool) _fit(int width, String left, String hint, String right) {
    final int leftBox = _displayWidth(left);
    final int hintBox = _displayWidth(hint) + _kSegmentGap * 2;
    final int rightBox = _displayWidth(right) + _kSegmentGap;
    final bool showRight = leftBox + hintBox + rightBox <= width;
    final int spare = width - leftBox - (showRight ? rightBox : 0);
    return (showRight, spare >= hintBox);
  }

  /// 三段布局：左段固定，中段 `Expanded` 独占剩余空间，右段贴右。
  ///
  /// 中段只能有**一个** flex 子件——早前这里叠了 `Spacer` + `Expanded`（都是
  /// `flex: 1`），中段被对半砍，提示裁掉半截还和右段撞在一起。
  Component _bar(String hint, bool showRight, bool showHint) {
    return Row(
      children: <Component>[
        Row(
          children: <Component>[
            if (permissionLabel.isNotEmpty)
              Text(
                permissionLabel,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(color: Colors.brightYellow),
              ),
            Text(
              permissionLabel.isEmpty ? modelLabel : '   $modelLabel',
              maxLines: 1,
              softWrap: false,
            ),
          ],
        ),
        Expanded(
          child: showHint
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: _kSegmentGap.toDouble()),
                  child: Text(
                    hint,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: busy ? Colors.brightYellow : Colors.gray,
                    ),
                  ),
                )
              : const SizedBox(),
        ),
        Text(
          showRight ? _rightText() : '',
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(color: Colors.gray),
        ),
      ],
    );
  }

  /// 左段：权限模式 + 模型标签。
  String _leftText() {
    return permissionLabel.isEmpty
        ? modelLabel
        : '$permissionLabel   $modelLabel';
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

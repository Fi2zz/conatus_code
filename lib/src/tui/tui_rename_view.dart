/// 会话重命名浮层：单行标题输入，Enter 提交、Esc 取消。
///
/// 输入只改本地 [TuiRenamePrompt.text]；提交前不碰会话（不追加任何事件）。
/// 按键在根组件处理（见 `tui.dart`），本组件只渲染状态与输入框。
library;

import 'package:nocterm/nocterm.dart';

import 'theme/nava_theme.dart';

/// 重命名浮层状态。
class TuiRenamePrompt {
  TuiRenamePrompt({this.onChanged});

  /// 状态变化回调（组件据此重绘）。
  void Function()? onChanged;

  /// 输入框控制器（文本即待提交标题）。
  final TextEditingController input = TextEditingController();

  bool _open = false;
  String? _targetId;

  /// 浮层是否可见。
  bool get open => _open;

  /// 待重命名的会话 id；未打开为 `null`。
  String? get targetId => _targetId;

  /// 当前输入文本。
  String get text => input.text;

  /// 打开浮层并预填 [current]（可为 `null`）。不写会话。
  void show(String id, String? current) {
    _targetId = id;
    input.text = current ?? '';
    input.selection = TextSelection.collapsed(offset: input.text.length);
    _open = true;
    onChanged?.call();
  }

  /// 关闭浮层并丢弃输入（幂等）。不写会话。
  void close() {
    if (!_open) {
      return;
    }
    _open = false;
    _targetId = null;
    input.clear();
    onChanged?.call();
  }
}

/// 重命名浮层视图。
class TuiRenameView extends StatelessComponent {
  const TuiRenameView({super.key, required this.prompt, this.onKeyEvent});

  /// 浮层状态。
  final TuiRenamePrompt prompt;

  /// 输入框按键拦截（Enter 提交、Esc 取消；其余交给输入框）。
  final bool Function(KeyboardEvent event)? onKeyEvent;

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
            '重命名会话 ${prompt.targetId ?? ''}',
            style: TextStyle(
              color: NavaTheme.palette.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Enter 确认 · Esc 取消',
            style: TextStyle(color: NavaTheme.palette.muted),
          ),
          const SizedBox(height: 1),
          Row(
            children: <Component>[
              Text('> ', style: TextStyle(color: NavaTheme.palette.prompt)),
              Expanded(
                child: TextField(
                  // 稳定 key：面板重绘时保持元素身份，否则焦点丢失。
                  key: const ValueKey<String>('rename-input'),
                  controller: prompt.input,
                  focused: true,
                  placeholder: '输入新标题',
                  style: TextStyle(color: NavaTheme.palette.text),
                  onKeyEvent: onKeyEvent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 主题选择浮层：内置主题列表 + 当前标记，确认后由控制器应用。
///
/// 按键在根组件处理（见 `tui.dart`），本组件只渲染 [NavaTheme.names]。
library;

import 'dart:async';

import 'package:nocterm/nocterm.dart';

import 'nava_palette.dart';
import 'nava_theme.dart';

/// 主题选择浮层状态：选中下标与确认 / 取消。
class ThemePrompt {
  ThemePrompt({this.onChanged});

  /// 状态变化回调（组件据此重绘）。
  void Function()? onChanged;

  bool _open = false;
  int _index = 0;
  Completer<String?>? _pending;

  /// 浮层是否可见。
  bool get open => _open;

  /// 可选主题名。
  List<String> get names => NavaTheme.names;

  /// 当前选中下标。
  int get index => _index;

  /// 当前生效的主题名（渲染 `← 当前`）。
  String get current => NavaTheme.current;

  /// 当前选中主题名。
  String get selected => names[_index];

  /// 打开面板并等待用户确认（Enter）或取消（Esc）；取消返回 `null`。
  Future<String?> choose() {
    cancel();
    _index = names.indexOf(NavaTheme.current);
    if (_index < 0) {
      _index = 0;
    }
    final Completer<String?> completer = Completer<String?>();
    _pending = completer;
    _open = true;
    onChanged?.call();
    return completer.future;
  }

  /// 移动光标（越界钳制）。
  void move(int delta) {
    final int last = names.length - 1;
    final int next = _index + delta;
    _index = next < 0 ? 0 : (next > last ? last : next);
    onChanged?.call();
  }

  /// 确认当前选中项并关闭（Enter）。
  void confirm() {
    final Completer<String?>? pending = _pending;
    final String name = selected;
    _close();
    if (pending != null && !pending.isCompleted) {
      pending.complete(name);
    }
  }

  /// 取消选择并关闭（Esc）。
  void cancel() {
    final Completer<String?>? pending = _pending;
    _close();
    if (pending != null && !pending.isCompleted) {
      pending.complete(null);
    }
  }

  void _close() {
    _pending = null;
    _open = false;
    onChanged?.call();
  }
}

/// 主题选择浮层。
class ThemeView extends StatelessComponent {
  const ThemeView({
    super.key,
    required this.names,
    required this.selected,
    required this.current,
  });

  /// 可选主题名。
  final List<String> names;

  /// 当前选中下标。
  final int selected;

  /// 当前生效的主题名。
  final String current;

  @override
  Component build(BuildContext context) {
    final NavaPalette palette = NavaTheme.palette;
    return Container(
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(border: BoxBorder.all(color: palette.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          Text(
            '主题（↑↓ 选择，Enter 应用，Esc 关闭）',
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          for (int i = 0; i < names.length; i++)
            _row(names[i], i == selected, names[i] == current),
        ],
      ),
    );
  }

  Component _row(String name, bool isSelected, bool isCurrent) {
    final NavaPalette palette = NavaTheme.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: isSelected ? palette.selected : null,
      child: Row(
        children: <Component>[
          Text(
            '${isSelected ? '>' : ' '} $name',
            style: TextStyle(
              color: isSelected ? palette.selectedText : palette.text,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (isCurrent) ...<Component>[
            const Text(' '),
            Text('← 当前', style: TextStyle(color: palette.warning)),
          ],
        ],
      ),
    );
  }
}

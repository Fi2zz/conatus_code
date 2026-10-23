/// `/diff` 交互式视图：左侧文件树 + 右侧统一 diff，全屏只读。
///
/// 按键与临时状态（当前文件、已读集合、滚动位置）在这里，关闭即丢弃。
library;

import 'package:nocterm/nocterm.dart';

import '../tui/theme/nava_theme.dart';
import 'diff_model.dart';
import 'tui_diff_panels.dart';
import 'tui_diff_parts.dart';

/// `/diff` 全屏视图；数据与范围由控制器持有。
class TuiDiffView extends StatefulComponent {
  const TuiDiffView({
    super.key,
    required this.diffs,
    required this.scope,
    this.notice,
    this.onClose,
    this.onSwitchScope,
  });

  /// 待展示的文件差异（已按路径排序）。
  final List<FileDiff> diffs;

  /// 当前比较范围。
  final DiffScope scope;

  /// 数据源降级说明（git 不可用、检查点缺失等）；正常为 `null`。
  final String? notice;

  /// 关闭视图（`q` / `Esc`）。
  final void Function()? onClose;

  /// 切换比较范围（`d`）；由控制器重新加载数据。
  final void Function(DiffScope scope)? onSwitchScope;

  @override
  State<TuiDiffView> createState() => _TuiDiffViewState();
}

class _TuiDiffViewState extends State<TuiDiffView> {
  int _index = 0;
  late DiffScope _scope = component.scope;
  final Set<String> _reviewed = <String>{};
  final ScrollController _scroll = ScrollController();
  final ScrollController _tree = ScrollController();

  FileDiff? get _current =>
      _index < component.diffs.length ? component.diffs[_index] : null;

  @override
  void didUpdateComponent(TuiDiffView oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.scope != component.scope) {
      _scope = component.scope;
      _index = 0;
      _reset();
    } else if (_index >= component.diffs.length) {
      _index = component.diffs.isEmpty ? 0 : component.diffs.length - 1;
      _reset();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _tree.dispose();
    super.dispose();
  }

  /// 回到文件顶部，并保证树里的选中项可见。
  void _reset() {
    _scroll.jumpTo(0);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _tree.ensureIndexVisible(index: _index);
      }
    });
  }

  void _select(int delta) {
    final int next = _index + delta;
    if (next < 0 || next >= component.diffs.length) {
      return;
    }
    setState(() => _index = next);
    _reset();
  }

  void _switchScope() {
    final DiffScope next = _scope == DiffScope.working
        ? DiffScope.turn
        : DiffScope.working;
    setState(() {
      _scope = next;
      _index = 0;
    });
    _reset();
    component.onSwitchScope?.call(next);
  }

  void _toggleReviewed() {
    final FileDiff? current = _current;
    if (current == null) {
      return;
    }
    setState(() {
      if (!_reviewed.add(current.path)) {
        _reviewed.remove(current.path);
      }
    });
  }

  // REASON: 按键是一张扁平分派表，分支数由交互约定决定，拆开反而更难读。
  bool _onKey(KeyboardEvent event) {
    final LogicalKey key = event.logicalKey;
    if (key == LogicalKey.keyJ || key == LogicalKey.arrowDown) {
      _scroll.scrollDown();
      return true;
    }
    if (key == LogicalKey.keyK || key == LogicalKey.arrowUp) {
      _scroll.scrollUp();
      return true;
    }
    switch (key) {
      case LogicalKey.keyN:
        _select(1);
      case LogicalKey.keyP:
        _select(-1);
      case LogicalKey.keyD:
        _switchScope();
      case LogicalKey.keyM:
        _toggleReviewed();
      case LogicalKey.keyQ || LogicalKey.escape:
        component.onClose?.call();
      default:
        return false;
    }
    return true;
  }

  @override
  Component build(BuildContext context) {
    return Focusable(
      focused: true,
      onKeyEvent: _onKey,
      child: Container(
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          border: BoxBorder.all(color: NavaTheme.palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Component>[
            TuiDiffHeader(
              scope: _scope,
              reviewed: _reviewed.length,
              notice: component.notice,
            ),
            const SizedBox(height: 1),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  /// 空结果显示提示；有文件时左右分栏。
  Component _content() {
    final FileDiff? current = _current;
    if (current == null) {
      return Center(
        child: Text(
          diffEmptyMessage(_scope),
          style: TextStyle(color: NavaTheme.palette.muted),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Component>[
        SizedBox(
          width: 32,
          child: TuiDiffTreePane(
            diffs: component.diffs,
            index: _index,
            reviewed: _reviewed,
            controller: _tree,
          ),
        ),
        const VerticalDivider(),
        Expanded(
          child: TuiDiffPane(diff: current, controller: _scroll),
        ),
      ],
    );
  }
}

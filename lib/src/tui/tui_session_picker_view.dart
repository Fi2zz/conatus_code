/// 会话选择面板：`↑↓` 选择、`Enter` 切换、`r` 重命名、`d` 删除、`Esc` 关闭
/// （按键在根组件处理）。
///
/// 列表随选中项滚动：会话数超过可视高度时，光标不会滚出画面。
library;

import 'package:nocterm/nocterm.dart';

import 'theme/nava_theme.dart';
import 'tui_session_picker.dart';
import 'tui_views.dart';

/// 会话选择面板视图。
class SessionPickerView extends StatefulComponent {
  const SessionPickerView({
    super.key,
    required this.sessions,
    required this.currentId,
    required this.selected,
  });

  /// 会话列表。
  final List<TuiSessionInfo> sessions;

  /// 当前会话 id。
  final String currentId;

  /// 当前选中下标。
  final int selected;

  @override
  State<SessionPickerView> createState() => _SessionPickerViewState();
}

class _SessionPickerViewState extends State<SessionPickerView> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _ensureSelectedVisible();
  }

  @override
  void didUpdateComponent(SessionPickerView oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.selected != component.selected ||
        oldComponent.sessions.length != component.sessions.length) {
      _ensureSelectedVisible();
    }
  }

  /// 帧后定位：首帧 render object 尚未 attach，需等布局完成再滚动。
  void _ensureSelectedVisible() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scroll.ensureIndexVisible(index: component.selected);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final List<TuiSessionInfo> sessions = component.sessions;
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
            '会话（↑↓ 选择，Enter 切换，r 重命名，d 删除，Esc 关闭）',
            style: TextStyle(
              color: NavaTheme.palette.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          if (sessions.isEmpty)
            Text(
              '暂无会话；直接输入开始对话，或 /new 开一个。',
              style: TextStyle(color: NavaTheme.palette.muted),
            )
          else
            SizedBox(
              // 面板贴在输入栏上方，父 Column 高度无界：列表按会话数取高，
              // 超过 10 行在面板内滚动，而不是把整屏撑爆。
              height: sessions.length.clamp(1, 10).toDouble(),
              child: ListView.builder(
                controller: _scroll,
                itemCount: sessions.length,
                itemBuilder: (BuildContext context, int index) =>
                    _row(sessions[index], index == component.selected),
              ),
            ),
        ],
      ),
    );
  }

  Component _row(TuiSessionInfo session, bool isSelected) {
    final String mark = session.id == component.currentId ? '*' : ' ';
    final String cursor = isSelected ? '>' : ' ';
    final String title = session.title?.trim() ?? '';
    final String label = title.isEmpty ? '未命名会话' : title;
    final String detail = <String>[
      shortSessionId(session.id),
      timeAgo(session.updatedAt),
      if (session.active) '${session.events} 条事件',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: isSelected ? NavaTheme.palette.selected : null,
      child: Text(
        '$cursor$mark $label  $detail',
        style: TextStyle(
          color: isSelected
              ? NavaTheme.palette.selectedText
              : NavaTheme.palette.text,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

/// 会话标签的视图态：只记录会话 id、标题与聊天滚动位置。
///
/// 标签是纯视图状态，不持有 Agent Loop，也不参与会话持久化。同一时刻只有
/// 一个活跃标签——后台标签不会继续流式输出（单活）。关闭标签只移除视图态，
/// 会话数据由 [SessionStore] 负责，不在这里删除。
library;

/// 标签容量上限（再多的会话请走 `/sessions` 面板）。
const int kTabCap = 8;

/// 一个会话标签。
class SessionTab {
  SessionTab({required this.sessionId, this.title = '', this.scrollOffset = 0});

  /// 会话 id。
  final String sessionId;

  /// 展示标题（会话标题；旧会话缺省为空，由渲染层回退短 id）。
  String title;

  /// 离开该标签时的聊天滚动位置。
  double scrollOffset;
}

/// 标签集合与唯一活跃标签。
class TabManager {
  final List<SessionTab> _tabs = <SessionTab>[];

  /// 记录过滚动位置的会话（区分「从未滚动」与「停在顶部」）。
  final Set<String> _scrollSaved = <String>{};
  int _active = -1;

  /// 当前标签（按打开顺序）。
  List<SessionTab> get tabs => List<SessionTab>.unmodifiable(_tabs);

  /// 活跃标签下标；空集合为 `-1`。
  int get active => _active;

  /// 活跃标签；空集合为 `null`。
  SessionTab? get activeTab =>
      _active >= 0 && _active < _tabs.length ? _tabs[_active] : null;

  /// 是否还能新增标签。
  bool get canAdd => _tabs.length < kTabCap;

  /// 会话是否已有标签。
  bool contains(String sessionId) => indexOf(sessionId) >= 0;

  /// 会话所在下标；不存在为 `-1`。
  int indexOf(String sessionId) =>
      _tabs.indexWhere((SessionTab tab) => tab.sessionId == sessionId);

  /// 打开标签并激活。
  ///
  /// 已存在时只更新标题并激活，不重复添加；达到 [kTabCap] 后不再新增
  /// （调用方应先查 [canAdd] 并提示）。
  void open(String sessionId, {String? title}) {
    final int existing = indexOf(sessionId);
    if (existing >= 0) {
      if (title != null) {
        _tabs[existing].title = title;
      }
      _active = existing;
      return;
    }
    if (!canAdd) {
      return;
    }
    _tabs.add(SessionTab(sessionId: sessionId, title: title ?? ''));
    _active = _tabs.length - 1;
  }

  /// 激活指定标签；越界忽略。
  void activate(int index) {
    if (index < 0 || index >= _tabs.length) {
      return;
    }
    _active = index;
  }

  /// 关闭指定标签。
  ///
  /// 关闭活跃标签时切到邻居（优先后一个，越界则前一个）；关闭后没有标签时
  /// 活跃下标回到 `-1`，由上层决定补一个新标签。
  void close(int index) {
    if (index < 0 || index >= _tabs.length) {
      return;
    }
    _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      _active = -1;
      return;
    }
    if (index < _active) {
      _active--;
      return;
    }
    if (index == _active) {
      _active = index.clamp(0, _tabs.length - 1);
    }
  }

  /// 更新标签标题（重命名后同步）。
  void retitle(String sessionId, String title) {
    final int index = indexOf(sessionId);
    if (index >= 0) {
      _tabs[index].title = title;
    }
  }

  /// 保存当前活跃标签的滚动位置；无活跃标签忽略。
  void saveScroll(double offset) {
    final SessionTab? tab = activeTab;
    if (tab != null) {
      tab.scrollOffset = offset;
      _scrollSaved.add(tab.sessionId);
    }
  }

  /// 活跃标签是否记录过滚动位置（新标签不强制跳到顶部）。
  bool get activeScrollSaved {
    final SessionTab? tab = activeTab;
    return tab != null && _scrollSaved.contains(tab.sessionId);
  }

  /// 活跃标签的滚动位置；无活跃标签返回 `0`。
  double restoreScroll() => activeTab?.scrollOffset ?? 0;
}

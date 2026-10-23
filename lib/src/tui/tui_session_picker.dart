/// TUI 会话选择面板状态：汇合活跃与已持久化会话、移动光标、取选中 id。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 会话面板中的一行。
class TuiSessionInfo {
  const TuiSessionInfo({
    required this.id,
    required this.active,
    required this.events,
    this.updatedAt,
    this.title,
  });

  /// 会话 id。
  final String id;

  /// 是否在内存中已打开。
  final bool active;

  /// 已记录的事件数（未打开时为 0）。
  final int events;

  /// 最近一次事件时间（未打开或空会话为 `null`）。
  final DateTime? updatedAt;

  /// 展示标题：会话标题事件；旧会话回退首条用户消息的前 40 字符。
  final String? title;
}

/// 面板标题预览的最大字符数。
const int kTuiSessionTitlePreview = 40;

/// 从事件流派生展示标题：首条 `user/message` 的文本前 40 字符。
///
/// 只读派生，不写回会话——旧会话（无标题事件）不会因此多出一条标题事件。
String? deriveSessionTitle(List<SessionEvent> events) {
  for (final SessionEvent event in events) {
    if (event.type != kUserMessageEvent) {
      continue;
    }
    final Object? data = event.data;
    if (data is! Map) {
      continue;
    }
    final Object? text = data['text'];
    if (text is! String) {
      continue;
    }
    final String flat = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (flat.isEmpty) {
      continue;
    }
    return flat.length <= kTuiSessionTitlePreview
        ? flat
        : flat.substring(0, kTuiSessionTitlePreview);
  }
  return null;
}

/// 短会话 id：去掉 `session_` 前缀，最多 8 字符（面板窄，完整 id 换行）。
String shortSessionId(String id) {
  const String prefix = 'session_';
  final String body = id.startsWith(prefix) ? id.substring(prefix.length) : id;
  return body.length <= 8 ? body : body.substring(0, 8);
}

/// 会话选择面板状态。
class TuiSessionPicker {
  TuiSessionPicker(this._sessions, {required this.onChanged});

  final SessionStore _sessions;

  /// 状态变化回调。
  final void Function() onChanged;

  /// 面板是否打开。
  bool open = false;

  /// 会话列表。
  List<TuiSessionInfo> list = const <TuiSessionInfo>[];

  /// 当前光标。
  int index = 0;

  /// 打开面板：汇合活跃会话与已持久化会话，并定位到当前会话。
  ///
  /// 已持久化但未打开的会话经 [SessionStore.open] 载入事件，用来展示标题与
  /// 更新时间；标题只读派生（无标题事件时取首条用户消息），不回写会话。
  Future<void> show(String currentId) async {
    final Set<String> ids = <String>{
      ..._sessions.ids,
      ...await _sessions.persistedIds(),
    };
    final List<TuiSessionInfo> infos = <TuiSessionInfo>[];
    for (final String id in ids) {
      final Session? opened = _sessions.get(id);
      final bool active = opened != null;
      final Session session = opened ?? await _sessions.open(id);
      final List<SessionEvent> events = session.events;
      infos.add(TuiSessionInfo(
        id: id,
        active: active,
        events: events.length,
        updatedAt: events.isEmpty ? null : events.last.time,
        title: session.title ?? deriveSessionTitle(events),
      ));
    }
    infos.sort((TuiSessionInfo a, TuiSessionInfo b) => a.id.compareTo(b.id));
    list = infos;
    index = list.indexWhere((TuiSessionInfo info) => info.id == currentId);
    if (index < 0) {
      index = 0;
    }
    open = true;
    onChanged();
  }

  /// 关闭面板。
  void close() {
    open = false;
    onChanged();
  }

  /// 移动光标（越界钳制；空列表无操作）。
  void move(int delta) {
    if (list.isEmpty) {
      return;
    }
    final int next = index + delta;
    index = next < 0 ? 0 : (next >= list.length ? list.length - 1 : next);
    onChanged();
  }

  /// 当前选中会话 id；空列表返回 `null`。
  String? selectedId() => list.isEmpty ? null : list[index].id;
}

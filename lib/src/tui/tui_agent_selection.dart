/// 会话级 Agent 选择：以 `agent/selected` 事件持久化，切回会话即恢复。
///
/// 控制器上的 `_agentId` 只是当前绑定的缓存；真正的归属在会话事件里，否则
/// 标签 / 会话会互相泄漏（在一个标签切到 `plan`，新标签也变 `plan`）。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// Agent 选择事件类型。
const String kAgentSelectedEvent = 'agent/selected';

/// 折叠会话自身后缀里最后一个 `agent/selected`；没有记录返回 `null`。
///
/// 只折叠 [Session.ownEvents]：fork 出的会话不继承父会话的选择。
String? restoreAgentId(Session session) {
  for (final SessionEvent event in session.ownEvents.reversed) {
    if (event.type != kAgentSelectedEvent) continue;
    final Object? data = event.data;
    if (data is Map) {
      final Object? id = data['id'];
      final String value = id == null ? '' : '$id'.trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }
  return null;
}

/// 把 [id] 写入会话；已有同一选择时不重复追加。
void persistAgentSelection(Session session, String id) {
  if (restoreAgentId(session) == id) return;
  session.append(kAgentSelectedEvent, data: <String, Object?>{'id': id});
}

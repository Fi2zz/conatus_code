/// 会话展示辅助：短 id（列表 / 标签栏共用）。
library;

/// 短会话 id：去掉 `session_` 前缀，最多 12 字符（面板窄，完整 id 换行）。
String shortSessionId(String id) {
  const String prefix = 'session_';
  final String body = id.startsWith(prefix) ? id.substring(prefix.length) : id;
  return body.length <= 12 ? body : body.substring(0, 12);
}

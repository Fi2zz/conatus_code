/// OpenCode 字段读取的公共小工具。
library;

/// 非空字符串；其它类型返回 `null`。
String? openCodeString(Object? raw) {
  if (raw is! String) return null;
  final String trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// `provider/model#variant` → `provider/model`，并告警 `#variant` 不支持。
String? openCodeModelField(
  Object? raw,
  String source,
  String field,
  List<String> warnings,
) {
  final String? value = openCodeString(raw);
  if (value == null) return null;
  final int hash = value.indexOf('#');
  if (hash <= 0) return value;
  warnings.add('$source: $field.model 的 #variant 暂不支持，已去掉（$value）。');
  return value.substring(0, hash);
}

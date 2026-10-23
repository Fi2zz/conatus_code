/// Agent frontmatter 标量字段读取：类型收窄。
library;

/// 读取可选字符串字段；非字符串视为格式错误。
String? agentStringField(Map<String, Object?> fields, String key) {
  final Object? value = fields[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('字段 $key 必须是字符串');
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// 读取可选布尔字段；非布尔视为格式错误。
bool agentBoolField(Map<String, Object?> fields, String key) {
  final Object? value = fields[key];
  if (value == null) return false;
  if (value is! bool) {
    throw FormatException('字段 $key 必须是布尔值');
  }
  return value;
}

/// 读取可选正整数步数；非正整数视为格式错误。
int? agentStepsField(Map<String, Object?> fields) {
  final Object? value = fields['steps'];
  if (value == null) return null;
  if (value is! int || value <= 0) {
    throw const FormatException('字段 steps 必须是正整数');
  }
  return value;
}

/// 配置值读取：TOML 映射的类型收窄与取值校验。
library;

/// 配置内容不合法（类型不符或取值越界）。
class ConfigException implements Exception {
  const ConfigException(this.message);

  /// 面向用户的说明，含出错位置与字段名。
  final String message;

  @override
  String toString() => 'ConfigException: $message';
}

/// 读取基类：持有已解析的顶层表与来源路径，提供逐字段收窄。
///
/// 字段缺失一律回落默认值；类型不符立刻抛 [ConfigException]，不静默转换。
class ConfigValues {
  ConfigValues(this.raw, this.source);

  /// 已解析的 TOML 顶层表。
  final Map<String, dynamic> raw;

  /// 出错信息里引用的来源（文件路径）。
  final String source;

  /// 取子表；缺失返回空表。
  Map<String, dynamic> readTable(String key) {
    final Object? value = raw[key];
    if (value == null) return const <String, dynamic>{};
    if (value is! Map) throw ConfigException('$source：[$key] 必须是表。');
    return value.cast<String, dynamic>();
  }

  /// 取非空字符串；缺失或空串返回 `null`。
  String? readString(Map<String, dynamic> table, String key) {
    final Object? value = table[key];
    if (value == null) return null;
    if (value is! String) throw ConfigException('$source：$key 必须是字符串。');
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 取布尔值；缺失返回 [fallback]。
  bool readBool(Map<String, dynamic> table, String key, bool fallback) {
    final Object? value = table[key];
    if (value == null) return fallback;
    if (value is! bool) throw ConfigException('$source：$key 必须是布尔值。');
    return value;
  }

  /// 取正整数；缺失返回 [fallback]。
  int readPositiveInt(Map<String, dynamic> table, String key, int fallback) {
    final Object? value = table[key];
    if (value == null) return fallback;
    if (value is! int || value <= 0) {
      throw ConfigException('$source：$key 必须是正整数。');
    }
    return value;
  }

  /// 取非负整数上限；缺失返回 [fallback]，`0` 表示不限（返回 null）。
  int? readBudgetLimit(Map<String, dynamic> table, String key, int fallback) {
    final Object? value = table[key];
    if (value == null) return fallback;
    if (value is! int || value < 0) {
      throw ConfigException('$source：$key 必须是非负整数。');
    }
    return value == 0 ? null : value;
  }

  /// 取字符串数组；缺失返回空列表。
  List<String> readStringList(Map<String, dynamic> table, String key) {
    final Object? value = table[key];
    if (value == null) return const <String>[];
    if (value is! List) throw ConfigException('$source：$key 必须是字符串数组。');
    return <String>[for (final Object? item in value) readListItem(key, item)];
  }

  /// 取字符串数组或字符串表里的单个元素。
  String readListItem(String key, Object? item) {
    if (item is String) return item;
    throw ConfigException('$source：$key 的元素必须是字符串。');
  }
}

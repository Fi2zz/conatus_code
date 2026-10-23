/// Agent `tools` 字段解析：白名单数组与 OpenCode 逐工具开关。
library;

import 'agent_open_code.dart';

/// `tools` 字段的解析结果：显式白名单与被显式禁用的工具。
///
/// 数组形式给出白名单（空数组 = 禁止所有工具）；OpenCode 表形式给出的是
/// 逐工具开关，`false` 项进入 [disabled]，`true` 项保持默认启用。
class AgentTools {
  /// 构造解析结果。
  const AgentTools({this.whitelist, this.disabled = const <String>[]});

  /// 显式白名单；`null` 表示未使用数组形式。
  final List<String>? whitelist;

  /// 表形式里值为 `false` 的工具（已映射为 nava 工具名）。
  final List<String> disabled;
}

/// 读取 `tools`：字符串数组是白名单，`tool: bool` 表是逐工具开关。
AgentTools agentToolsField(Map<String, Object?> fields) {
  final Object? value = fields['tools'];
  if (value == null) return const AgentTools();
  if (value is List) {
    return AgentTools(
      whitelist: <String>[
        for (final Object? item in value) _toolListEntry(item),
      ],
    );
  }
  if (value is Map) return AgentTools(disabled: _disabledTools(value));
  throw const FormatException('字段 tools 必须是字符串数组或布尔表');
}

String _toolListEntry(Object? item) {
  if (item is! String || item.trim().isEmpty) {
    throw const FormatException('字段 tools 的元素必须是非空字符串');
  }
  return mapAgentToolName(item);
}

List<String> _disabledTools(Map<Object?, Object?> table) {
  final List<String> names = <String>[];
  for (final MapEntry<Object?, Object?> entry in table.entries) {
    final Object? key = entry.key;
    if (key is! String || key.trim().isEmpty) {
      throw const FormatException('字段 tools 的键必须是非空字符串');
    }
    if (entry.value is! bool) {
      throw FormatException('字段 tools 的 $key 必须是布尔值');
    }
    if (!(entry.value as bool)) names.add(mapAgentToolName(key));
  }
  return names;
}

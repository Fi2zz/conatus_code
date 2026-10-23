/// Agent frontmatter 字段读取：类型收窄与 OpenCode 兼容转换。
library;

import 'package:conatus_agent/conatus_agent.dart'
    show
        PermissionEffect,
        PermissionRule,
        normalizePermissionPath,
        permissionActionUsesPath;

import 'agent_open_code.dart';

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

/// 读取工具白名单：字符串数组或 `tool: bool` 表；只保留 `true` 项。
///
/// 表形式兼容 OpenCode（`tools: {write: false, read: true}`），空表与空数组
/// 都表示禁止所有工具；`null` 表示不额外限制。
List<String>? agentToolsField(Map<String, Object?> fields) {
  final Object? value = fields['tools'];
  if (value == null) return null;
  if (value is List) {
    return <String>[for (final Object? item in value) _toolListEntry(item)];
  }
  if (value is Map) return _enabledTools(value);
  throw const FormatException('字段 tools 必须是字符串数组或布尔表');
}

String _toolListEntry(Object? item) {
  if (item is! String || item.trim().isEmpty) {
    throw const FormatException('字段 tools 的元素必须是非空字符串');
  }
  return mapAgentToolName(item);
}

List<String> _enabledTools(Map<Object?, Object?> table) {
  final List<String> names = <String>[];
  for (final MapEntry<Object?, Object?> entry in table.entries) {
    final Object? key = entry.key;
    if (key is! String || key.trim().isEmpty) {
      throw const FormatException('字段 tools 的键必须是非空字符串');
    }
    if (entry.value is! bool) {
      throw FormatException('字段 tools 的 $key 必须是布尔值');
    }
    if (entry.value as bool) names.add(mapAgentToolName(key));
  }
  return names;
}

/// 读取权限规则：`permissions` 数组在前，OpenCode `permission` 映射在后。
///
/// 映射形式每条资源固定为 `*`，追加在数组之后；权限引擎「最后匹配生效」，
/// 因此两者同时出现时映射形式优先。
List<PermissionRule> agentPermissionsField(
  Map<String, Object?> fields,
  List<String> warnings,
) => <PermissionRule>[
  ..._permissionList(fields['permissions'], warnings),
  ..._permissionMap(fields['permission'], warnings),
];

List<PermissionRule> _permissionList(Object? value, List<String> warnings) {
  if (value == null) return const <PermissionRule>[];
  if (value is! List) {
    throw const FormatException('字段 permissions 必须是表数组');
  }
  return <PermissionRule>[
    for (final Object? item in value) _permissionRule(item, warnings),
  ];
}

PermissionRule _permissionRule(Object? item, List<String> warnings) {
  if (item is! Map) {
    throw const FormatException('字段 permissions 的每一项必须是表');
  }
  return _rule(
    _permissionField(item, 'action'),
    _permissionField(item, 'resource'),
    _permissionField(item, 'effect'),
    warnings,
  );
}

List<PermissionRule> _permissionMap(Object? value, List<String> warnings) {
  if (value == null) return const <PermissionRule>[];
  if (value is! Map) {
    throw const FormatException('字段 permission 必须是动作到效果的映射');
  }
  return <PermissionRule>[
    for (final MapEntry<Object?, Object?> entry in value.entries)
      _rule(
        _mapAction(entry.key, 'permission'),
        '*',
        _mapEffect(entry.key, entry.value),
        warnings,
      ),
  ];
}

String _mapAction(Object? key, String field) {
  if (key is! String || key.trim().isEmpty) {
    throw FormatException('字段 $field 的键必须是非空字符串');
  }
  return key;
}

String _mapEffect(Object? key, Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      '字段 permission 的 ${_mapAction(key, 'permission')} 必须是字符串',
    );
  }
  return value;
}

PermissionRule _rule(
  String rawAction,
  String resource,
  String rawEffect,
  List<String> warnings,
) {
  final String action = normalizeAgentAction(rawAction);
  if (!agentActionKnown(rawAction, action)) {
    warnings.add('权限动作 "$rawAction" 不是已知动作，按原值保留');
  }
  return PermissionRule(
    action: action,
    resource: permissionActionUsesPath(action)
        ? normalizePermissionPath(resource)
        : resource,
    effect: _permissionEffect(rawEffect),
    source: 'agent',
  );
}

String _permissionField(Map<Object?, Object?> table, String key) {
  final Object? value = table[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('权限字段 $key 不能为空');
  }
  return value.trim();
}

PermissionEffect _permissionEffect(String value) {
  for (final PermissionEffect effect in PermissionEffect.values) {
    if (effect.name == value) return effect;
  }
  throw const FormatException('权限字段 effect 必须是 allow/ask/deny');
}

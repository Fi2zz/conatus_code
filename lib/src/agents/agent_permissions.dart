/// Agent 权限字段解析：`permissions` 数组与 OpenCode `permission` 映射。
library;

import 'package:conatus_agent/conatus_agent.dart'
    show
        PermissionEffect,
        PermissionRule,
        normalizePermissionPath,
        permissionActionUsesPath;

import 'agent_open_code.dart';

/// 读取权限规则：`permissions` 数组在前，OpenCode `permission` 映射在后。
///
/// 映射形式每个动作可以是效果字符串（资源 `*`），也可以是
/// `pattern: effect` 嵌套映射（如 `bash: {"git diff": allow}`）；规则追加在
/// 数组之后，权限引擎「最后匹配生效」，因此两者同时出现时映射形式优先。
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
    for (final Object? item in value)
      if (_permissionRule(item, warnings) case final PermissionRule rule) rule,
  ];
}

PermissionRule? _permissionRule(Object? item, List<String> warnings) {
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
  final List<PermissionRule> rules = <PermissionRule>[];
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    final String action = _mapAction(entry.key, 'permission');
    rules.addAll(_actionRules(action, entry.value, warnings));
  }
  return rules;
}

List<PermissionRule> _actionRules(
  String rawAction,
  Object? value,
  List<String> warnings,
) {
  if (value is String) {
    final PermissionRule? rule = _rule(rawAction, '*', value, warnings);
    return <PermissionRule>[if (rule != null) rule];
  }
  if (value is! Map) {
    throw FormatException(
      '字段 permission 的 $rawAction 必须是效果字符串或 pattern: effect 映射',
    );
  }
  return <PermissionRule>[
    for (final MapEntry<Object?, Object?> entry in value.entries)
      if (_rule(
            rawAction,
            _mapAction(entry.key, 'permission.$rawAction'),
            _effectValue(entry.value, 'permission.$rawAction'),
            warnings,
          )
          case final PermissionRule rule)
        rule,
  ];
}

String _mapAction(Object? key, String field) {
  if (key is! String || key.trim().isEmpty) {
    throw FormatException('字段 $field 的键必须是非空字符串');
  }
  return key;
}

String _effectValue(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('字段 $field 的效果必须是字符串');
  }
  return value;
}

PermissionRule? _rule(
  String rawAction,
  String resource,
  String rawEffect,
  List<String> warnings,
) {
  if (!agentActionSupported(rawAction)) {
    warnings.add('权限动作 "$rawAction" 在 nava 中没有对应工具，已忽略该规则');
    return null;
  }
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

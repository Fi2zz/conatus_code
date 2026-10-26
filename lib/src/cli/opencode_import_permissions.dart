/// OpenCode `permissions` 数组 → nava 权限规则，动作名归一化。
library;

import '../agents/agent_open_code.dart';
import 'opencode_import_types.dart';

/// 映射规则；不支持的 OpenCode 动作告警跳过。
List<ImportedPermission> mapOpenCodePermissions(
  Object? raw,
  String source,
  List<String> warnings,
) {
  if (raw == null) return const <ImportedPermission>[];
  if (raw is! List) {
    warnings.add('$source: permissions 必须是数组，已忽略。');
    return const <ImportedPermission>[];
  }
  final List<ImportedPermission> result = <ImportedPermission>[];
  for (final Object? item in raw) {
    final ImportedPermission? rule = _permission(item, source, warnings);
    if (rule != null) result.add(rule);
  }
  return result;
}

ImportedPermission? _permission(
  Object? raw,
  String source,
  List<String> warnings,
) {
  if (raw is! Map) {
    warnings.add('$source: permissions 的条目必须是对象，已跳过。');
    return null;
  }
  final Object? rawAction = raw['action'];
  if (rawAction is! String || rawAction.trim().isEmpty) {
    warnings.add('$source: permissions 缺少 action，已跳过。');
    return null;
  }
  final String action = rawAction.trim();
  if (!agentActionSupported(action)) {
    warnings.add('$source: permissions 的 $action 动作 nava 暂无对应工具，已跳过。');
    return null;
  }
  final String? effect = _string(
    raw['effect'],
    'permissions.effect',
    source,
    warnings,
  );
  if (effect == null || !const <String>{'allow', 'ask', 'deny'}.contains(effect)) {
    warnings.add('$source: permissions 的 effect "$effect" 不合法，已跳过。');
    return null;
  }
  final String resource =
      _string(raw['resource'], 'permissions.resource', source, warnings) ?? '*';
  return ImportedPermission(
    action: normalizeAgentAction(action),
    resource: resource,
    effect: effect,
  );
}

String? _string(
  Object? raw,
  String field,
  String source,
  List<String> warnings,
) {
  if (raw == null) return null;
  if (raw is! String) {
    warnings.add('$source: $field 必须是字符串，已忽略。');
    return null;
  }
  final String trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

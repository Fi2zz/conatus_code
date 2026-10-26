/// OpenCode `agents` JSON 定义 → 待物化的 Markdown 模型。
library;

import 'opencode_import_fields.dart';
import 'opencode_import_permissions.dart';
import 'opencode_import_types.dart';

/// 映射 `agents` 对象；同 ID 覆盖由调用方负责。
List<ImportedAgent> mapOpenCodeAgents(
  Object? raw,
  String source,
  bool global,
  List<String> warnings,
) {
  if (raw == null) return const <ImportedAgent>[];
  if (raw is! Map) {
    warnings.add('$source: agents 必须是对象，已忽略。');
    return const <ImportedAgent>[];
  }
  final List<ImportedAgent> result = <ImportedAgent>[];
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    final String id = entry.key.toString().trim();
    final ImportedAgent? agent = _agent(id, entry.value, source, global, warnings);
    if (agent != null) result.add(agent);
  }
  return result;
}

ImportedAgent? _agent(
  String id,
  Object? raw,
  String source,
  bool global,
  List<String> warnings,
) {
  if (id.isEmpty) {
    warnings.add('$source: agents 有空 ID，已跳过。');
    return null;
  }
  if (raw is! Map) {
    warnings.add('$source: agents.$id 必须是对象，已跳过。');
    return null;
  }
  if (raw['disabled'] == true) {
    warnings.add('$source: agents.$id disabled = true，已跳过。');
    return null;
  }
  final String system = openCodeString(raw['system']) ?? '';
  final String? description = openCodeString(raw['description']);
  if (system.isEmpty && description == null) {
    warnings.add('$source: agents.$id 既没有 system 也没有 description，已跳过。');
    return null;
  }
  _warnUnsupported(raw, source, 'agents.$id', warnings);
  return ImportedAgent(
    id: id,
    system: system,
    global: global,
    description: description,
    mode: _mode(raw['mode'], source, id, warnings),
    model: openCodeModelField(raw['model'], source, 'agents.$id', warnings),
    steps: _steps(raw['steps'], source, id, warnings),
    permissions: mapOpenCodePermissions(
      raw['permissions'],
      '$source: agents.$id',
      warnings,
    ),
  );
}

String? _mode(
  Object? raw,
  String source,
  String id,
  List<String> warnings,
) {
  if (raw == null) return null;
  if (raw is! String) {
    warnings.add('$source: agents.$id mode 必须是字符串，已忽略。');
    return null;
  }
  final String value = raw.trim();
  if (const <String>{'primary', 'subagent', 'all'}.contains(value)) {
    return value;
  }
  warnings.add('$source: agents.$id mode "$value" 不合法，已忽略。');
  return null;
}

int? _steps(
  Object? raw,
  String source,
  String id,
  List<String> warnings,
) {
  if (raw == null) return null;
  if (raw is int && raw > 0) return raw;
  warnings.add('$source: agents.$id steps 必须是正整数，已忽略。');
  return null;
}

void _warnUnsupported(
  Map<Object?, Object?> raw,
  String source,
  String field,
  List<String> warnings,
) {
  for (final String key in const <String>['tools', 'hidden', 'color', 'request']) {
    if (raw[key] != null) {
      warnings.add('$source: $field.$key 暂不支持，已忽略。');
    }
  }
}

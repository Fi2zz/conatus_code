/// Agent 文档解析：frontmatter 元数据 + 正文系统提示。
library;

import 'package:conatus_agent/conatus_agent.dart'
    show
        PermissionEffect,
        PermissionRule,
        normalizePermissionPath,
        permissionActionFor,
        permissionActionUsesPath;
import 'package:conatus_skill/conatus_skill.dart';

import 'agent_definition.dart';

/// 一次 Agent 解析的结果；失败时 [error] 说明原因。
class AgentParseResult {
  /// 解析成功。
  const AgentParseResult.success(this.definition) : error = null;

  /// 解析失败，[error] 为可展示的原因。
  const AgentParseResult.failure(this.error) : definition = null;

  /// 成功时的 Agent 定义。
  final AgentDefinition? definition;

  /// 失败原因；成功时为 `null`。
  final String? error;
}

/// 解析一份 Agent Markdown。
///
/// 没有 frontmatter 时整篇正文作为系统提示；字段类型错误、YAML 非法或闭合
/// 围栏缺失时返回 `null`，由调用方跳过该文件并记录警告。
AgentDefinition? parseAgentDocument(
  String text, {
  required String id,
  required String sourcePath,
}) =>
    parseAgentDocumentDetailed(text, id: id, sourcePath: sourcePath).definition;

/// 与 [parseAgentDocument] 相同，但失败时给出可诊断的原因。
AgentParseResult parseAgentDocumentDetailed(
  String text, {
  required String id,
  required String sourcePath,
}) {
  final String trimmedId = id.trim();
  if (trimmedId.isEmpty) {
    return const AgentParseResult.failure('Agent 名称为空');
  }
  final FrontmatterDocument document = _document(text);
  if (document.error != null) {
    return AgentParseResult.failure('frontmatter 解析失败：${document.error}');
  }
  try {
    return AgentParseResult.success(
      _definition(document, trimmedId, sourcePath),
    );
  } on FormatException catch (error) {
    return AgentParseResult.failure(error.message);
  }
}

AgentDefinition _definition(
  FrontmatterDocument document,
  String id,
  String sourcePath,
) {
  final Map<String, Object?> fields = document.fields;
  final String? mode = _stringField(fields, 'mode');
  return AgentDefinition(
    id: id,
    sourcePath: sourcePath,
    description: _stringField(fields, 'description') ?? '',
    mode: mode == null ? AgentMode.primary : AgentMode.parse(mode),
    system: document.body,
    model: _stringField(fields, 'model'),
    steps: _stepsField(fields),
    tools: _toolsField(fields),
    permissions: _permissionsField(fields),
    hidden: _boolField(fields, 'hidden'),
    color: _stringField(fields, 'color'),
  );
}

/// 有围栏则交给通用解析器；没有围栏视作纯正文。
FrontmatterDocument _document(String text) {
  final String first = text.split('\n').first.replaceAll('\r', '');
  if (first != '---') {
    return FrontmatterDocument(
      fields: const <String, Object?>{},
      body: text.trim(),
    );
  }
  final FrontmatterDocument parsed = parseFrontmatter(text);
  if (parsed.error == null) return parsed;
  return _emptyFrontmatter(text) ?? parsed;
}

/// 只有围栏、没有字段的 frontmatter 等价于空映射。
FrontmatterDocument? _emptyFrontmatter(String text) {
  final List<String> lines = text.split('\n');
  for (int index = 1; index < lines.length; index++) {
    if (lines[index].replaceAll('\r', '') != '---') continue;
    if (lines.sublist(1, index).join('\n').trim().isNotEmpty) return null;
    return FrontmatterDocument(
      fields: const <String, Object?>{},
      body: lines.sublist(index + 1).join('\n').trim(),
    );
  }
  return null;
}

String? _stringField(Map<String, Object?> fields, String key) {
  final Object? value = fields[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('字段 $key 必须是字符串');
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _boolField(Map<String, Object?> fields, String key) {
  final Object? value = fields[key];
  if (value == null) return false;
  if (value is! bool) {
    throw FormatException('字段 $key 必须是布尔值');
  }
  return value;
}

int? _stepsField(Map<String, Object?> fields) {
  final Object? value = fields['steps'];
  if (value == null) return null;
  if (value is! int || value <= 0) {
    throw const FormatException('字段 steps 必须是正整数');
  }
  return value;
}

List<String>? _toolsField(Map<String, Object?> fields) {
  final Object? value = fields['tools'];
  if (value == null) return null;
  if (value is! List) {
    throw const FormatException('字段 tools 必须是字符串数组');
  }
  return <String>[for (final Object? item in value) _toolEntry(item)];
}

String _toolEntry(Object? item) {
  if (item is! String || item.trim().isEmpty) {
    throw const FormatException('字段 tools 的元素必须是非空字符串');
  }
  return item.trim();
}

List<PermissionRule> _permissionsField(Map<String, Object?> fields) {
  final Object? value = fields['permissions'];
  if (value == null) return const <PermissionRule>[];
  if (value is! List) {
    throw const FormatException('字段 permissions 必须是表数组');
  }
  return <PermissionRule>[
    for (final Object? item in value) _permissionRule(item),
  ];
}

PermissionRule _permissionRule(Object? item) {
  if (item is! Map) {
    throw const FormatException('字段 permissions 的每一项必须是表');
  }
  final String action = permissionActionFor(_permissionField(item, 'action'));
  final String resource = _permissionField(item, 'resource');
  return PermissionRule(
    action: action,
    resource: permissionActionUsesPath(action)
        ? normalizePermissionPath(resource)
        : resource,
    effect: _permissionEffect(_permissionField(item, 'effect')),
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

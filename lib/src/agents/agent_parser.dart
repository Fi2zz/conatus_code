/// Agent 文档解析：frontmatter 元数据 + 正文系统提示。
library;

import 'package:conatus_skill/conatus_skill.dart';

import 'agent_definition.dart';
import 'agent_fields.dart';

/// 一次 Agent 解析的结果；失败时 [error] 说明原因。
class AgentParseResult {
  /// 解析成功；[definition] 必须非空。
  const AgentParseResult.success(
    AgentDefinition definition, {
    List<String> warnings = const <String>[],
  }) : this._(definition, null, warnings);

  /// 解析失败；[message] 必须非空。
  const AgentParseResult.failure(
    String message, {
    List<String> warnings = const <String>[],
  }) : this._(null, message, warnings);

  const AgentParseResult._(this.definition, this.error, this.warnings);

  /// 成功时的 Agent 定义。
  final AgentDefinition? definition;

  /// 失败原因；成功时为 `null`。
  final String? error;

  /// 非致命提示（如未知权限动作、frontmatter 围栏格式异常）。
  final List<String> warnings;
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
  final List<String> warnings = <String>[];
  final FrontmatterDocument document = _document(text, warnings);
  if (document.error != null) {
    return AgentParseResult.failure(
      'frontmatter 解析失败：${document.error}',
      warnings: _snapshot(warnings),
    );
  }
  try {
    return AgentParseResult.success(
      _definition(document, trimmedId, sourcePath, warnings),
      warnings: _snapshot(warnings),
    );
  } on FormatException catch (error) {
    return AgentParseResult.failure(
      error.message,
      warnings: _snapshot(warnings),
    );
  }
}

List<String> _snapshot(List<String> warnings) =>
    List<String>.unmodifiable(warnings);

AgentDefinition _definition(
  FrontmatterDocument document,
  String id,
  String sourcePath,
  List<String> warnings,
) {
  final Map<String, Object?> fields = document.fields;
  final String? mode = agentStringField(fields, 'mode');
  return AgentDefinition(
    id: id,
    sourcePath: sourcePath,
    description: agentStringField(fields, 'description') ?? '',
    mode: mode == null ? AgentMode.primary : AgentMode.parse(mode),
    system: document.body,
    model: agentStringField(fields, 'model'),
    steps: agentStepsField(fields),
    tools: agentToolsField(fields),
    permissions: agentPermissionsField(fields, warnings),
    hidden: agentBoolField(fields, 'hidden'),
    color: agentStringField(fields, 'color'),
  );
}

/// 有围栏则交给通用解析器；没有围栏视作纯正文。
FrontmatterDocument _document(String text, List<String> warnings) {
  final String normalized = _normalizeDocument(text);
  final String first = normalized.split('\n').first.replaceAll('\r', '');
  if (first != '---') {
    if (normalized.startsWith('---')) {
      warnings.add('frontmatter 首行必须是独占一行的 ---，已按纯正文解析');
    }
    return FrontmatterDocument(
      fields: const <String, Object?>{},
      body: normalized.trim(),
    );
  }
  final FrontmatterDocument parsed = parseFrontmatter(normalized);
  if (parsed.error == null) return parsed;
  return _emptyFrontmatter(normalized) ?? parsed;
}

/// 去掉 BOM 与前导空行，避免它们让 frontmatter 围栏失效。
String _normalizeDocument(String text) {
  final String withoutBom = text.startsWith('\uFEFF')
      ? text.substring(1)
      : text;
  final List<String> lines = withoutBom.split('\n');
  int start = 0;
  while (start < lines.length && lines[start].trim().isEmpty) {
    start++;
  }
  return lines.sublist(start).join('\n');
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

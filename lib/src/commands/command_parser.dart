/// 命令文档解析：frontmatter 元数据 + 正文模板。
library;

import 'package:conatus_skill/conatus_skill.dart';

import 'command_definition.dart';

/// 一次命令解析的结果；失败时 [error] 说明原因。
class CommandParseResult {
  /// 解析成功。
  const CommandParseResult.success(this.definition) : error = null;

  /// 解析失败，[error] 为可展示的原因。
  const CommandParseResult.failure(this.error) : definition = null;

  /// 成功时的命令定义。
  final CommandDefinition? definition;

  /// 失败原因；成功时为 `null`。
  final String? error;
}

/// 解析一份命令 Markdown。
///
/// 所有 frontmatter 字段都是可选的；完全没有 frontmatter 时整篇正文作为
/// 模板。字段类型错误、YAML 非法或闭合围栏缺失时返回 `null`，由调用方
/// 跳过该文件并记录警告。空名称同样返回 `null`。
CommandDefinition? parseCommandDocument(
  String text, {
  required String name,
  required String sourcePath,
}) => parseCommandDocumentDetailed(
  text,
  name: name,
  sourcePath: sourcePath,
).definition;

/// 与 [parseCommandDocument] 相同，但失败时给出可诊断的原因。
CommandParseResult parseCommandDocumentDetailed(
  String text, {
  required String name,
  required String sourcePath,
}) {
  final String trimmedName = name.trim();
  if (trimmedName.isEmpty) {
    return const CommandParseResult.failure('命令名称为空');
  }
  final FrontmatterDocument document = _document(text);
  if (document.error != null) {
    return CommandParseResult.failure('frontmatter 解析失败：${document.error}');
  }
  try {
    return CommandParseResult.success(
      CommandDefinition(
        name: trimmedName,
        description: _stringField(document.fields, 'description') ?? '',
        template: document.body,
        agent: _stringField(document.fields, 'agent'),
        model: _stringField(document.fields, 'model'),
        subagent: _boolField(document.fields, 'subagent'),
        sourcePath: sourcePath,
      ),
    );
  } on FormatException catch (error) {
    return CommandParseResult.failure(error.message);
  }
}

/// 有围栏则交给通用解析器；没有围栏视作纯模板。
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

/// 只有围栏、没有字段的 frontmatter 等价于空映射（字段全部缺省）。
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

/// 读取可选字符串字段；非字符串视为格式错误。
String? _stringField(Map<String, Object?> fields, String key) {
  final Object? value = fields[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('字段 $key 必须是字符串');
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// 读取可选布尔字段；非布尔视为格式错误。
bool _boolField(Map<String, Object?> fields, String key) {
  final Object? value = fields[key];
  if (value == null) return false;
  if (value is! bool) {
    throw FormatException('字段 $key 必须是布尔值');
  }
  return value;
}

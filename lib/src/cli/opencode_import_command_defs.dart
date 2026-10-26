/// OpenCode `commands` JSON 定义 → 待物化的 Markdown 模型。
library;

import 'opencode_import_fields.dart';
import 'opencode_import_types.dart';

/// 映射 `commands` 对象；同名覆盖由调用方负责。
List<ImportedCommand> mapOpenCodeCommands(
  Object? raw,
  String source,
  bool global,
  List<String> warnings,
) {
  if (raw == null) return const <ImportedCommand>[];
  if (raw is! Map) {
    warnings.add('$source: commands 必须是对象，已忽略。');
    return const <ImportedCommand>[];
  }
  final List<ImportedCommand> result = <ImportedCommand>[];
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    final String name = entry.key.toString().trim();
    final ImportedCommand? command = _command(
      name,
      entry.value,
      source,
      global,
      warnings,
    );
    if (command != null) result.add(command);
  }
  return result;
}

ImportedCommand? _command(
  String name,
  Object? raw,
  String source,
  bool global,
  List<String> warnings,
) {
  if (name.isEmpty) {
    warnings.add('$source: commands 有空名称，已跳过。');
    return null;
  }
  if (raw is! Map) {
    warnings.add('$source: commands.$name 必须是对象，已跳过。');
    return null;
  }
  if (raw['disabled'] == true) {
    warnings.add('$source: commands.$name disabled = true，已跳过。');
    return null;
  }
  final String? template = openCodeString(raw['template']);
  if (template == null) {
    warnings.add('$source: commands.$name 缺少 template，已跳过。');
    return null;
  }
  return ImportedCommand(
    name: name,
    template: template,
    global: global,
    description: openCodeString(raw['description']),
    agent: openCodeString(raw['agent']),
    model: openCodeModelField(raw['model'], source, 'commands.$name', warnings),
    subagent: _subagent(raw, source, name, warnings),
  );
}

bool? _subagent(
  Map<Object?, Object?> raw,
  String source,
  String name,
  List<String> warnings,
) {
  if (raw['subagent'] is bool) return raw['subagent'] as bool;
  if (raw['subtask'] is bool) {
    warnings.add('$source: commands.$name 使用已弃用的 subtask，按 subagent 处理。');
    return raw['subtask'] as bool;
  }
  return null;
}

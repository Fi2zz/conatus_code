/// OpenCode JSON agents / commands → nava Markdown 定义文件。
///
/// 物化到 `.nava/agents` / `.nava/commands`（全局或项目），由现有注册表发现；
/// 已存在的文件不覆盖，交由用户自己合并。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'opencode_import_types.dart';

/// 一个待写入的定义文件。
class ImportedDefinitionFile {
  const ImportedDefinitionFile({
    required this.path,
    required this.content,
    required this.label,
  });

  final String path;
  final String content;
  final String label;
}

/// 定义文件计划。
class DefinitionFilePlan {
  const DefinitionFilePlan({required this.files, required this.skipped});

  final List<ImportedDefinitionFile> files;
  final List<String> skipped;

  bool get hasChanges => files.isNotEmpty;
}

/// 计算 agents / commands 的物化文件；[homeDir] 缺省取真实用户目录。
DefinitionFilePlan planOpenCodeDefinitionFiles({
  required OpenCodeImport import,
  required String workdir,
  String? homeDir,
}) {
  final String home = homeDir ?? resolveHomeDir();
  final List<ImportedDefinitionFile> files = <ImportedDefinitionFile>[];
  final List<String> skipped = <String>[];
  for (final ImportedAgent agent in import.agents) {
    _plan(
      base: agent.global ? '$home/.nava/agents' : '$workdir/.nava/agents',
      id: agent.id,
      label: 'agent ${agent.id}',
      content: renderAgentMarkdown(agent),
      files: files,
      skipped: skipped,
    );
  }
  for (final ImportedCommand command in import.commands) {
    _plan(
      base: command.global ? '$home/.nava/commands' : '$workdir/.nava/commands',
      id: command.name,
      label: 'command ${command.name}',
      content: renderCommandMarkdown(command),
      files: files,
      skipped: skipped,
    );
  }
  return DefinitionFilePlan(files: files, skipped: skipped);
}

void _plan({
  required String base,
  required String id,
  required String label,
  required String content,
  required List<ImportedDefinitionFile> files,
  required List<String> skipped,
}) {
  final String? path = _definitionPath(base, id);
  if (path == null) {
    skipped.add('$label（ID 含不安全路径，已跳过）');
    return;
  }
  if (File(path).existsSync()) {
    skipped.add('$label（文件已存在：$path）');
    return;
  }
  files.add(ImportedDefinitionFile(path: path, content: content, label: label));
}

/// Agent 文件：frontmatter + system 正文。
String renderAgentMarkdown(ImportedAgent agent) {
  final StringBuffer buffer = StringBuffer('---\n');
  if (agent.description != null) {
    buffer.writeln('description: ${_yaml(agent.description!)}');
  }
  if (agent.mode != null) buffer.writeln('mode: ${agent.mode}');
  if (agent.model != null) buffer.writeln('model: ${_yaml(agent.model!)}');
  if (agent.steps != null) buffer.writeln('steps: ${agent.steps}');
  if (agent.permissions.isNotEmpty) {
    buffer.writeln('permissions:');
    for (final ImportedPermission rule in agent.permissions) {
      buffer
        ..writeln('  - action: ${_yaml(rule.action)}')
        ..writeln('    resource: ${_yaml(rule.resource)}')
        ..writeln('    effect: ${_yaml(rule.effect)}');
    }
  }
  buffer.writeln('---');
  if (agent.system.isNotEmpty) buffer.writeln(agent.system);
  return buffer.toString();
}

/// 命令文件：frontmatter + template 正文。
String renderCommandMarkdown(ImportedCommand command) {
  final StringBuffer buffer = StringBuffer('---\n');
  if (command.description != null) {
    buffer.writeln('description: ${_yaml(command.description!)}');
  }
  if (command.agent != null) buffer.writeln('agent: ${_yaml(command.agent!)}');
  if (command.model != null) buffer.writeln('model: ${_yaml(command.model!)}');
  if (command.subagent != null) {
    buffer.writeln('subagent: ${command.subagent}');
  }
  buffer
    ..writeln('---')
    ..writeln(command.template);
  return buffer.toString();
}

String? _definitionPath(String base, String id) {
  if (id.startsWith('/') || id.contains('\\') || id.contains('\x00')) {
    return null;
  }
  final List<String> segments = id.split('/');
  if (segments.any((String part) => part.isEmpty || part == '.' || part == '..')) {
    return null;
  }
  final String relative = segments.join(Platform.pathSeparator);
  return '$base${Platform.pathSeparator}$relative.md';
}

/// YAML 双引号字符串；控制字符用转义，避免 frontmatter 被截断。
String _yaml(String value) {
  final StringBuffer buffer = StringBuffer('"');
  for (final int rune in value.runes) {
    switch (rune) {
      case 0x22:
        buffer.write(r'\"');
      case 0x5C:
        buffer.write(r'\\');
      case 0x0A:
        buffer.write(r'\n');
      case 0x0D:
        buffer.write(r'\r');
      case 0x09:
        buffer.write(r'\t');
      default:
        if (rune < 0x20) {
          buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
        } else {
          buffer.write(String.fromCharCode(rune));
        }
    }
  }
  buffer.write('"');
  return buffer.toString();
}

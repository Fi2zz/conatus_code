/// OpenCode 导入的公共类型。
library;

import '../config/config_schema.dart';

/// 一条待写入 `[[permissions]]` 的规则。
class ImportedPermission {
  const ImportedPermission({
    required this.action,
    required this.resource,
    required this.effect,
  });

  final String action;
  final String resource;
  final String effect;
}

/// 从 OpenCode 配置提取出的、可写入 nava config.toml 的字段。
class OpenCodeImport {
  const OpenCodeImport({
    this.model,
    this.defaultAgent,
    this.mcpServers = const <McpServerSpec>[],
    this.permissions = const <ImportedPermission>[],
    this.instructions = const <String>[],
    this.agents = const <ImportedAgent>[],
    this.commands = const <ImportedCommand>[],
    this.warnings = const <String>[],
  });

  final String? model;
  final String? defaultAgent;
  final List<McpServerSpec> mcpServers;
  final List<ImportedPermission> permissions;
  final List<String> instructions;
  final List<ImportedAgent> agents;
  final List<ImportedCommand> commands;
  final List<String> warnings;

  bool get isEmpty =>
      model == null &&
      defaultAgent == null &&
      mcpServers.isEmpty &&
      permissions.isEmpty &&
      instructions.isEmpty &&
      agents.isEmpty &&
      commands.isEmpty;
}

/// OpenCode JSON 里定义的一个 Agent，待物化为 `.nava/agents/<id>.md`。
class ImportedAgent {
  const ImportedAgent({
    required this.id,
    required this.system,
    required this.global,
    this.description,
    this.mode,
    this.model,
    this.steps,
    this.permissions = const <ImportedPermission>[],
  });

  final String id;
  final String system;
  final bool global;
  final String? description;
  final String? mode;
  final String? model;
  final int? steps;
  final List<ImportedPermission> permissions;
}

/// OpenCode JSON 里定义的一条命令，待物化为 `.nava/commands/<name>.md`。
class ImportedCommand {
  const ImportedCommand({
    required this.name,
    required this.template,
    required this.global,
    this.description,
    this.agent,
    this.model,
    this.subagent,
  });

  final String name;
  final String template;
  final bool global;
  final String? description;
  final String? agent;
  final String? model;
  final bool? subagent;
}

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
    this.skillDirs = const <String>[],
    this.providers = const <ImportedProvider>[],
    this.references = const <ImportedReference>[],
    this.agents = const <ImportedAgent>[],
    this.commands = const <ImportedCommand>[],
    this.warnings = const <String>[],
  });

  final String? model;
  final String? defaultAgent;
  final List<McpServerSpec> mcpServers;
  final List<ImportedPermission> permissions;
  final List<String> instructions;
  final List<String> skillDirs;
  final List<ImportedProvider> providers;
  final List<ImportedReference> references;
  final List<ImportedAgent> agents;
  final List<ImportedCommand> commands;
  final List<String> warnings;

  bool get isEmpty =>
      model == null &&
      defaultAgent == null &&
      mcpServers.isEmpty &&
      permissions.isEmpty &&
      instructions.isEmpty &&
      skillDirs.isEmpty &&
      providers.isEmpty &&
      references.isEmpty &&
      agents.isEmpty &&
      commands.isEmpty;
}

/// OpenCode `references.<name>` 里的一个本地目录。
class ImportedReference {
  const ImportedReference({
    required this.name,
    required this.path,
    this.description = '',
  });

  final String name;
  final String path;
  final String description;
}

/// OpenCode `providers.<name>` 里可导入的一个提供商。
class ImportedProvider {
  const ImportedProvider({
    required this.name,
    required this.baseUrl,
    required this.type,
    this.apiKey,
    this.credentialKey,
    this.models = const <ImportedModel>[],
  });

  final String name;
  final String baseUrl;
  final String type;
  final String? apiKey;
  final String? credentialKey;
  final List<ImportedModel> models;
}

/// 提供商下的一个模型元数据。
class ImportedModel {  const ImportedModel({
    required this.model,
    this.displayName = '',
    this.maxContext = 0,
  });

  final String model;
  final String displayName;
  final int maxContext;
}

/// OpenCode JSON 里定义的一个 Agent，待物化为 `.nava/agents/<id>.md`。
class ImportedAgent {  const ImportedAgent({
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

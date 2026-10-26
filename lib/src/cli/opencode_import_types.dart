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
    this.warnings = const <String>[],
  });

  final String? model;
  final String? defaultAgent;
  final List<McpServerSpec> mcpServers;
  final List<ImportedPermission> permissions;
  final List<String> instructions;
  final List<String> warnings;

  bool get isEmpty =>
      model == null &&
      defaultAgent == null &&
      mcpServers.isEmpty &&
      permissions.isEmpty &&
      instructions.isEmpty;
}

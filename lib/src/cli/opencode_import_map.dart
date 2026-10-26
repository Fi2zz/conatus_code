/// OpenCode 配置 → nava 导入模型（model / agent / MCP / permissions / instructions）。
///
/// 只映射 nava 真正支持的字段；`agents` / `commands` / `providers` / `plugins`
/// 等先告警跳过，避免写出运行时不生效的配置。
library;

import 'dart:io';

import '../config/config_schema.dart';
import 'opencode_import_command_defs.dart';
import 'opencode_import_definitions.dart';
import 'opencode_import_mcp.dart';
import 'opencode_import_permissions.dart';
import 'opencode_import_providers.dart';
import 'opencode_import_source.dart';
import 'opencode_import_types.dart';

const List<String> _ignoredKeys = <String>[
  'plugins',
  'lsp',
  'references',
  'policies',
  'formatter',
  'tools',
];

/// 按文档顺序合并并映射；后者覆盖标量与同名 MCP，permissions/instructions 追加。
OpenCodeImport buildOpenCodeImport(OpenCodeSources sources) {
  final List<String> warnings = <String>[...sources.warnings];
  final Map<String, McpServerSpec> mcp = <String, McpServerSpec>{};
  final List<ImportedPermission> permissions = <ImportedPermission>[];
  final List<String> instructions = <String>[];
  final List<String> skillDirs = <String>[];
  final Set<String> seenSkillDirs = <String>{};
  final Map<String, ImportedProvider> providers = <String, ImportedProvider>{};
  final Set<String> ignored = <String>{};
  final Map<String, ImportedAgent> agents = <String, ImportedAgent>{};
  final Map<String, ImportedCommand> commands = <String, ImportedCommand>{};
  String? model;
  String? defaultAgent;
  for (final OpenCodeDocument document in sources.documents) {
    final Map<String, Object?> values = document.values;
    model = _model(values['model'], document.path, warnings) ?? model;
    defaultAgent =
        _string(values['default_agent'], 'default_agent', document.path, warnings) ??
        defaultAgent;
    _mcp(values['mcp'], document.path, warnings, mcp);
    permissions.addAll(
      mapOpenCodePermissions(values['permissions'], document.path, warnings),
    );
    instructions.addAll(
      _instructions(values['instructions'], document.path, warnings),
    );
    skillDirs.addAll(
      _skillDirs(
        values['skills'],
        sources.workdir,
        document.path,
        warnings,
        seenSkillDirs,
      ),
    );
    for (final ImportedAgent agent in mapOpenCodeAgents(
      values['agents'],
      document.path,
      document.global,
      warnings,
    )) {
      agents[agent.id] = agent;
    }
    for (final ImportedCommand command in mapOpenCodeCommands(
      values['commands'],
      document.path,
      document.global,
      warnings,
    )) {
      commands[command.name] = command;
    }
    ignored.addAll(_ignoredKeys.where(values.containsKey));
    for (final ImportedProvider provider in mapOpenCodeProviders(
      values['providers'],
      document.path,
      warnings,
    )) {
      providers[provider.name] = provider;
    }
  }
  for (final String key in _ignoredKeys) {
    if (!ignored.contains(key)) continue;
    if (key == 'plugins') {
      warnings.add('opencode 的 plugins 暂不支持（自定义工具请用 [[tools]] 或 MCP 包装）。');
      continue;
    }
    warnings.add('opencode 的 $key 暂不支持，已忽略。');
  }
  return OpenCodeImport(
    model: model,
    defaultAgent: defaultAgent,
    mcpServers: mcp.values.toList(growable: false),
    permissions: List<ImportedPermission>.unmodifiable(permissions),
    instructions: List<String>.unmodifiable(instructions),
    skillDirs: List<String>.unmodifiable(skillDirs),
    providers: providers.values.toList(growable: false),
    agents: agents.values.toList(growable: false),
    commands: commands.values.toList(growable: false),
    warnings: List<String>.unmodifiable(warnings),
  );
}

String? _model(Object? raw, String source, List<String> warnings) {
  final String? value = _string(raw, 'model', source, warnings);
  if (value == null) return null;
  final int hash = value.indexOf('#');
  if (hash <= 0) return value;
  warnings.add('$source: model 的 #variant 暂不支持，已去掉（$value）。');
  return value.substring(0, hash);
}

void _mcp(
  Object? raw,
  String source,
  List<String> warnings,
  Map<String, McpServerSpec> target,
) {
  if (raw == null) return;
  if (raw is! Map) {
    warnings.add('$source: mcp 必须是对象，已忽略。');
    return;
  }
  final Object? servers = raw['servers'];
  if (servers is! Map) {
    warnings.add('$source: mcp.servers 缺失或格式不对（V1 形状暂不支持），已忽略。');
    return;
  }
  for (final MapEntry<Object?, Object?> entry in servers.entries) {
    final String name = entry.key.toString().trim();
    if (name.isEmpty) continue;
    final McpServerSpec? spec = mapOpenCodeMcpServer(
      name: name,
      raw: entry.value,
      source: source,
      warnings: warnings,
    );
    if (spec != null) target[name] = spec;
  }
}

List<String> _skillDirs(
  Object? raw,
  String workdir,
  String source,
  List<String> warnings,
  Set<String> seen,
) {
  if (raw == null) return const <String>[];
  if (raw is! List) {
    warnings.add('$source: skills 必须是数组，已忽略。');
    return const <String>[];
  }
  final List<String> result = <String>[];
  for (final Object? item in raw) {
    if (item is! String) continue;
    final String value = item.trim();
    if (value.isEmpty) continue;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      warnings.add('$source: HTTP 技能目录暂不支持，已跳过：$value');
      continue;
    }
    String relative = value;
    while (relative.startsWith('./')) {
      relative = relative.substring(2);
    }
    if (relative.isEmpty) continue;
    final String path = value.startsWith('/') || value.startsWith('~')
        ? value
        : '$workdir${Platform.pathSeparator}'
            '${relative.replaceAll('/', Platform.pathSeparator)}';
    if (!seen.add(path)) continue;
    result.add(path);
  }
  return result;
}

List<String> _instructions(
  Object? raw,
  String source,
  List<String> warnings,
) {
  if (raw == null) return const <String>[];
  if (raw is! List) {
    warnings.add('$source: instructions 必须是数组，已忽略。');
    return const <String>[];
  }
  return <String>[
    for (final Object? item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
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

/// OpenCode 导入计划：只追加缺失项，已有同名配置一律跳过。
library;

import 'package:toml/toml.dart';

import '../config/config_schema.dart';
import 'opencode_import_toml.dart';
import 'opencode_import_types.dart';

/// 合并结果。
class OpenCodeImportPlan {
  const OpenCodeImportPlan({
    required this.updatedToml,
    required this.snippet,
    required this.added,
    required this.skipped,
  });

  /// 合并后的完整配置。
  final String updatedToml;

  /// 只包含新增项的可粘贴片段。
  final String snippet;

  /// 新增项标签。
  final List<String> added;

  /// 跳过项与原因。
  final List<String> skipped;

  bool get hasChanges => added.isNotEmpty;
}

/// 计算导入计划；现有 TOML 非法时抛 [FormatException]。
OpenCodeImportPlan planOpenCodeImport({
  required String toml,
  required OpenCodeImport import,
}) {
  final Map<String, Object?> existing = _parseExisting(toml);
  final List<String> added = <String>[];
  final List<String> skipped = <String>[];
  final String? model = _planModel(import.model, existing, added, skipped);
  final String? agent = _planAgent(import.defaultAgent, existing, added, skipped);
  final List<McpServerSpec> mcp = _planMcp(
    import.mcpServers,
    existing,
    added,
    skipped,
  );
  final List<ImportedPermission> permissions = _planPermissions(
    import.permissions,
    existing,
    added,
    skipped,
  );
  final List<String> instructions = _planInstructions(
    import.instructions,
    existing,
    added,
    skipped,
  );
  final List<String> skillDirs = _planSkillDirs(
    import.skillDirs,
    existing,
    added,
    skipped,
  );
  final List<ImportedProvider> providers = _planProviders(
    import.providers,
    existing,
    added,
    skipped,
  );
  final List<ImportedReference> references = _planReferences(
    import.references,
    existing,
    added,
    skipped,
  );
  final String updated = applyOpenCodeImport(
    toml,
    model: model,
    agent: agent,
    mcp: mcp,
    permissions: permissions,
    instructions: instructions,
    skillDirs: skillDirs,
    providers: providers,
    references: references,
  );
  ensureImportParseable(updated);
  return OpenCodeImportPlan(
    updatedToml: updated,
    snippet: applyOpenCodeImport(
      '',
      model: model,
      agent: agent,
      mcp: mcp,
      permissions: permissions,
      instructions: instructions,
      skillDirs: skillDirs,
      providers: providers,
      references: references,
    ).trim(),
    added: List<String>.unmodifiable(added),
    skipped: List<String>.unmodifiable(skipped),
  );
}

Map<String, Object?> _parseExisting(String toml) {
  if (toml.trim().isEmpty) return const <String, Object?>{};
  try {
    return Map<String, Object?>.from(TomlDocument.parse(toml).toMap());
  } on TomlException catch (error) {
    throw FormatException('现有配置不是合法 TOML：$error');
  }
}

String? _planModel(
  String? model,
  Map<String, Object?> existing,
  List<String> added,
  List<String> skipped,
) {
  if (model == null) return null;
  if (existing.containsKey('default_model') ||
      _hasPath(existing, <String>['llm', 'default_model'])) {
    skipped.add('model（已有 default_model）');
    return null;
  }
  added.add('model');
  return model;
}

String? _planAgent(
  String? agent,
  Map<String, Object?> existing,
  List<String> added,
  List<String> skipped,
) {
  if (agent == null) return null;
  if (_hasPath(existing, <String>['agent', 'default_agent'])) {
    skipped.add('default_agent（已有）');
    return null;
  }
  added.add('default_agent');
  return agent;
}

List<McpServerSpec> _planMcp(
  List<McpServerSpec> specs,
  Map<String, Object?> existing,
  List<String> added,
  List<String> skipped,
) {
  final List<McpServerSpec> keep = <McpServerSpec>[];
  for (final McpServerSpec spec in specs) {
    if (_hasPath(existing, <String>['mcp', 'servers', spec.name])) {
      skipped.add('mcp.${spec.name}（已有同名 server）');
      continue;
    }
    keep.add(spec);
    added.add('mcp.${spec.name}');
  }
  return keep;
}

List<ImportedPermission> _planPermissions(
  List<ImportedPermission> rules,
  Map<String, Object?> existing,
  List<String> added,
  List<String> skipped,
) {
  final Set<String> seen = _existingPermissions(existing);
  final List<ImportedPermission> keep = <ImportedPermission>[];
  for (final ImportedPermission rule in rules) {
    if (!seen.add(_permissionKey(rule))) {
      skipped.add('permission ${rule.action} ${rule.resource}（重复）');
      continue;
    }
    keep.add(rule);
    added.add('permission ${rule.action} ${rule.resource}');
  }
  return keep;
}

List<String> _planInstructions(
  List<String> instructions,
  Map<String, Object?> existing,
  List<String> added,
  List<String> skipped,
) {
  if (instructions.isEmpty) return const <String>[];
  if (existing.containsKey('instructions')) {
    skipped.add('instructions（已有顶层 instructions，未合并）');
    return const <String>[];
  }
  added.add('instructions');
  return instructions;
}

List<String> _planSkillDirs(
  List<String> skillDirs,
  Map<String, Object?> existing,
  List<String> added,
  List<String> skipped,
) {
  if (skillDirs.isEmpty) return const <String>[];
  if (existing.containsKey('extra_skill_dirs')) {
    skipped.add('skills（已有 extra_skill_dirs，未合并）');
    return const <String>[];
  }
  added.add('extra_skill_dirs');
  return skillDirs;
}

List<ImportedProvider> _planProviders(
  List<ImportedProvider> providers,
  Map<String, Object?> existing,
  List<String> added,
  List<String> skipped,
) {  final List<ImportedProvider> result = <ImportedProvider>[];
  for (final ImportedProvider provider in providers) {
    if (_hasPath(existing, <String>['providers', provider.name])) {
      skipped.add('provider ${provider.name}（已有）');
      continue;
    }
    final List<ImportedModel> models = <ImportedModel>[];
    for (final ImportedModel model in provider.models) {
      final String qualified = '${provider.name}/${model.model}';
      if (_hasPath(existing, <String>['models', qualified])) {
        skipped.add('model $qualified（已有）');
        continue;
      }
      models.add(model);
      added.add('model $qualified');
    }
    result.add(
      ImportedProvider(
        name: provider.name,
        baseUrl: provider.baseUrl,
        type: provider.type,
        apiKey: provider.apiKey,
        credentialKey: provider.credentialKey,
        models: List<ImportedModel>.unmodifiable(models),
      ),
    );
    added.add('provider ${provider.name}');
  }
  return result;
}

List<ImportedReference> _planReferences(
  List<ImportedReference> references,
  Map<String, Object?> existing,
  List<String> added,
  List<String> skipped,
) {
  final List<ImportedReference> result = <ImportedReference>[];
  for (final ImportedReference reference in references) {
    if (_hasPath(existing, <String>['references', reference.name])) {
      skipped.add('reference ${reference.name}（已有）');
      continue;
    }
    result.add(reference);
    added.add('reference ${reference.name}');
  }
  return result;
}

Set<String> _existingPermissions(Map<String, Object?> existing) {
  final Object? raw = existing['permissions'];
  if (raw is! List) return <String>{};
  return <String>{
    for (final Object? item in raw)
      if (item is Map)
        '${item['action']}\u0000${item['resource']}\u0000${item['effect']}',
  };
}

String _permissionKey(ImportedPermission rule) =>
    '${rule.action}\u0000${rule.resource}\u0000${rule.effect}';

bool _hasPath(Map<String, Object?> map, List<String> path) {
  Object? current = map;
  for (final String key in path) {
    if (current is! Map || !current.containsKey(key)) return false;
    current = current[key];
  }
  return true;
}

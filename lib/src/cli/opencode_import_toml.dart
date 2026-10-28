/// 导入 TOML 应用：追加 MCP / permissions / instructions，并更新 model / agent。
library;

import 'package:toml/toml.dart';

import '../config/config_schema.dart';
import '../config/config_toml.dart';
import '../config/config_writer.dart';
import 'opencode_import_render.dart';
import 'opencode_import_types.dart';

/// 把新增项应用到 [base]（空串可用于生成片段）。
String applyOpenCodeImport(
  String base, {
  String? model,
  String? agent,
  List<McpServerSpec> mcp = const <McpServerSpec>[],
  List<ImportedPermission> permissions = const <ImportedPermission>[],
  List<String> instructions = const <String>[],
  List<String> skillDirs = const <String>[],
  List<ImportedProvider> providers = const <ImportedProvider>[],
  List<ImportedReference> references = const <ImportedReference>[],
  LspConfig lsp = const LspConfig(),
}) {
  String out = base;
  if (model != null) out = upsertDefaultModel(out, model);
  if (agent != null) out = _upsertAgentDefault(out, agent);
  for (final ImportedReference reference in references) {
    out = _append(out, _renderReference(reference));
  }
  for (final ImportedProvider provider in providers) {
    out = appendProviderSection(
      out,
      name: provider.name,
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey ?? '',
      credentialKey: provider.credentialKey ?? '',
      type: provider.type,
    );
    for (final ImportedModel item in provider.models) {
      out = appendModelSection(
        out,
        provider: provider.name,
        entry: ModelEntry(
          id: item.model,
          displayName: item.displayName,
          maxContextSize: item.maxContext,
        ),
      );
    }
  }
  if (lsp.enabled || lsp.servers.isNotEmpty) {
    out = _append(out, _renderLsp(lsp));
  }
  for (final McpServerSpec spec in mcp) {
    out = _append(out, renderMcpSection(spec));
  }
  for (final ImportedPermission rule in permissions) {
    out = _append(out, renderPermissionBlock(rule));
  }
  if (instructions.isNotEmpty) {
    out = _insertTopLevelArray(out, renderInstructionsLine(instructions));
  }
  if (skillDirs.isNotEmpty) {
    out = _insertTopLevelArray(
      out,
      renderStringArrayLine('extra_skill_dirs', skillDirs),
    );
  }
  return base.trim().isEmpty ? out.trimLeft() : out;
}

/// 合并结果必须能重新解析，否则调用方放弃写盘。
void ensureImportParseable(String toml) {
  try {
    TomlDocument.parse(toml).toMap();
  } on TomlException catch (error) {
    throw FormatException('合并后的配置不是合法 TOML：$error');
  }
}

String _renderLsp(LspConfig lsp) {
  final StringBuffer buffer = StringBuffer('[lsp]\n');
  buffer.write('enabled = ${lsp.enabled}\n');
  for (final LspServerConfig server in lsp.servers) {
    final String key = tomlKey(server.name);
    buffer.write('\n[lsp.servers.$key]\n');
    buffer.write('command = [${server.command.map((String item) => '"${tomlString(item)}"').join(', ')}]\n');
    if (server.extensions.isNotEmpty) {
      buffer.write('extensions = [${server.extensions.map((String item) => '"${tomlString(item)}"').join(', ')}]\n');
    }
    if (server.env.isNotEmpty) {
      buffer.write('\n[lsp.servers.$key.env]\n');
      for (final MapEntry<String, String> item in server.env.entries) {
        buffer.write('${tomlKey(item.key)} = "${tomlString(item.value)}"\n');
      }
    }
    if (server.initialization.isNotEmpty) {
      buffer.write('\n[lsp.servers.$key.initialization]\n');
      for (final MapEntry<String, Object?> item in server.initialization.entries) {
        buffer.write('${tomlKey(item.key)} = ${_tomlValue(item.value)}\n');
      }
    }
  }
  return buffer.toString();
}

String _tomlValue(Object? value) {
  if (value is String) return '"${tomlString(value)}"';
  if (value is num || value is bool) return '$value';
  return '"${tomlString('$value')}"';
}

String _renderReference(ImportedReference reference) {
  final StringBuffer buffer = StringBuffer(
    '[references.${tomlKey(reference.name)}]\n',
  );
  buffer.write('path = "${tomlString(reference.path)}"\n');
  if (reference.description.isNotEmpty) {
    buffer.write('description = "${tomlString(reference.description)}"\n');
  }
  return buffer.toString();
}

String _upsertAgentDefault(String toml, String value) {
  final List<String> lines = toml.split('\n');
  final int start = lines.indexWhere((String line) => line.trim() == '[agent]');
  if (start < 0) {
    return _append(toml, '[agent]\ndefault_agent = "${tomlString(value)}"\n');
  }
  final int end = _sectionEnd(lines, start);
  final String assignment = 'default_agent = "${tomlString(value)}"';
  final int existing = _assignmentLine(lines, start, end, 'default_agent');
  if (existing >= 0) {
    lines[existing] = assignment;
  } else {
    lines.insert(start + 1, assignment);
  }
  return lines.join('\n');
}

int _sectionEnd(List<String> lines, int start) {
  for (int index = start + 1; index < lines.length; index++) {
    final String trimmed = lines[index].trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) return index;
  }
  return lines.length;
}

int _assignmentLine(List<String> lines, int start, int end, String key) {
  for (int index = start + 1; index < end; index++) {
    final String trimmed = lines[index].trim();
    if (!trimmed.startsWith('#') && trimmed.startsWith('$key =')) return index;
  }
  return -1;
}

String _insertTopLevelArray(String toml, String line) {
  final List<String> lines = toml.split('\n');
  final int firstTable = lines.indexWhere(_isTableHeader);
  if (firstTable < 0) return _append(toml, '$line\n');
  lines.insertAll(firstTable, <String>[line, '']);
  return lines.join('\n');
}

bool _isTableHeader(String line) {
  final String trimmed = line.trim();
  return trimmed.startsWith('[') && trimmed.endsWith(']');
}

String _append(String toml, String section) {
  final StringBuffer buffer = StringBuffer(toml);
  if (toml.isNotEmpty && !toml.endsWith('\n')) buffer.write('\n');
  if (toml.isNotEmpty) buffer.write('\n');
  buffer.write(section);
  if (!section.endsWith('\n')) buffer.write('\n');
  return buffer.toString();
}

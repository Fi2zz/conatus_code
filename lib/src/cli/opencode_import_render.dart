/// 导入项的 TOML 片段渲染。
library;

import '../config/config_schema.dart';
import '../config/config_toml.dart';
import 'opencode_import_types.dart';

/// `[mcp.servers.<name>]`（含 `.oauth` 子表）。
String renderMcpSection(McpServerSpec spec) {
  final StringBuffer buffer = StringBuffer(
    '[mcp.servers.${tomlKey(spec.name)}]\n',
  );
  if (spec.type == McpServerType.stdio) {
    buffer
      ..write('type = "stdio"\n')
      ..write('command = "${tomlString(spec.command!)}"\n');
    if (spec.args.isNotEmpty) {
      buffer.write('args = [ ${_strings(spec.args)} ]\n');
    }
    if (spec.env.isNotEmpty) {
      buffer.write('env = { ${_inlineMap(spec.env)} }\n');
    }
  } else {
    buffer
      ..write('type = "${spec.type.name}"\n')
      ..write('url = "${tomlString(spec.url!)}"\n');
    if (spec.headers.isNotEmpty) {
      buffer.write('headers = { ${_inlineMap(spec.headers)} }\n');
    }
  }
  _writeOAuth(buffer, spec);
  return buffer.toString();
}

/// 一段 `[[permissions]]`。
String renderPermissionBlock(ImportedPermission rule) =>
    '[[permissions]]\n'
    'action = "${tomlString(rule.action)}"\n'
    'resource = "${tomlString(rule.resource)}"\n'
    'effect = "${tomlString(rule.effect)}"\n';

/// 顶层 `instructions = [...]` 行。
String renderInstructionsLine(List<String> values) =>
    'instructions = [ ${_strings(values)} ]';

void _writeOAuth(StringBuffer buffer, McpServerSpec spec) {
  final oauth = spec.oauth;
  if (oauth == null) return;
  if (!oauth.enabled) {
    buffer.write('oauth = false\n');
    return;
  }
  final List<String> fields = <String>[
    if (oauth.clientId != null) 'client_id = "${tomlString(oauth.clientId!)}"',
    if (oauth.clientSecret != null)
      'client_secret = "${tomlString(oauth.clientSecret!)}"',
    if (oauth.scope != null) 'scope = "${tomlString(oauth.scope!)}"',
    if (oauth.callbackPort != null) 'callback_port = ${oauth.callbackPort}',
  ];
  if (fields.isEmpty) return;
  buffer
    ..write('\n[mcp.servers.${tomlKey(spec.name)}.oauth]\n')
    ..write(fields.join('\n'))
    ..write('\n');
}

String _strings(List<String> values) =>
    values.map((String value) => '"${tomlString(value)}"').join(', ');

String _inlineMap(Map<String, String> values) => values.entries
    .map((MapEntry<String, String> entry) =>
        '${tomlKey(entry.key)} = "${tomlString(entry.value)}"')
    .join(', ');

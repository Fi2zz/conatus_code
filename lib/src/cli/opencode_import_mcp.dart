/// OpenCode `mcp.servers.*` → [McpServerSpec]。
///
/// V2 形状：local 用 `command` 数组 + `environment`；remote 用 `url` +
/// `headers` + `oauth`。`{env:NAME}` 占位符转成 nava 的 `${NAME}`。
library;

import 'package:conatus_mcp/conatus_mcp.dart' show McpOAuthConfig;

import '../config/config_schema.dart';

/// 映射一台 server；无法映射时告警并返回 `null`。
McpServerSpec? mapOpenCodeMcpServer({
  required String name,
  required Object? raw,
  required String source,
  required List<String> warnings,
}) {
  if (raw is! Map) {
    _warn(warnings, source, name, '必须是对象，已跳过');
    return null;
  }
  final Map<Object?, Object?> table = Map<Object?, Object?>.from(raw);
  if (table['disabled'] == true) {
    _warn(warnings, source, name, 'disabled = true，已跳过');
    return null;
  }
  final String? type = _string(table['type']);
  final List<String> command = _commandList(table['command']);
  final String? url = _string(table['url']);
  final bool local = type == 'local' || type == 'stdio';
  final bool remote = type == 'remote' || type == 'http' || type == 'sse';
  if (local || (type == null && command.isNotEmpty)) {
    return _local(name, table, command, source, warnings);
  }
  if (remote || (type == null && url != null)) {
    return _remote(name, table, url, type, source, warnings);
  }
  _warn(warnings, source, name, '缺少 command / url 或 type 非法，已跳过');
  return null;
}

McpServerSpec? _local(
  String name,
  Map<Object?, Object?> raw,
  List<String> command,
  String source,
  List<String> warnings,
) {
  if (command.isEmpty) {
    _warn(warnings, source, name, 'local 缺少 command，已跳过');
    return null;
  }
  if (raw['cwd'] != null) {
    _warn(warnings, source, name, 'cwd 暂不支持，已忽略');
  }
  return McpServerSpec(
    name: name,
    type: McpServerType.stdio,
    command: command.first,
    args: command.sublist(1),
    env: _stringMap(raw['environment'] ?? raw['env'], source, name, warnings),
  );
}

McpServerSpec? _remote(
  String name,
  Map<Object?, Object?> raw,
  String? url,
  String? type,
  String source,
  List<String> warnings,
) {
  if (url == null) {
    _warn(warnings, source, name, 'remote 缺少 url，已跳过');
    return null;
  }
  return McpServerSpec(
    name: name,
    type: type == 'sse' ? McpServerType.sse : McpServerType.http,
    url: url,
    headers: _stringMap(raw['headers'], source, name, warnings),
    oauth: _oauth(raw['oauth'], source, name, warnings),
  );
}

McpOAuthConfig? _oauth(
  Object? raw,
  String source,
  String name,
  List<String> warnings,
) {
  if (raw == null || raw == true) return null;
  if (raw == false) return const McpOAuthConfig(enabled: false);
  if (raw is! Map) {
    _warn(warnings, source, name, 'oauth 必须是布尔值或对象，已忽略');
    return null;
  }
  final int? callbackPort = _port(raw['callback_port'], source, name, warnings);
  for (final String key in const <String>[
    'redirect_uri',
    'auth_server_metadata_url',
  ]) {
    if (raw[key] != null) {
      _warn(warnings, source, name, 'oauth.$key 暂不支持，已忽略');
    }
  }
  return McpOAuthConfig(
    clientId: _string(raw['client_id']),
    clientSecret: _string(raw['client_secret']),
    scope: _string(raw['scope']),
    callbackPort: callbackPort,
  );
}

int? _port(
  Object? raw,
  String source,
  String name,
  List<String> warnings,
) {
  if (raw == null) return null;
  if (raw is int && raw >= 1 && raw <= 65535) return raw;
  _warn(warnings, source, name, 'oauth.callback_port 必须是 1-65535 的整数，已忽略');
  return null;
}

List<String> _commandList(Object? raw) {
  if (raw is String) return <String>[raw];
  if (raw is! List) return const <String>[];
  return <String>[for (final Object? item in raw) if (item is String) item];
}

Map<String, String> _stringMap(
  Object? raw,
  String source,
  String name,
  List<String> warnings,
) {
  if (raw is! Map) return const <String, String>{};
  final Map<String, String> result = <String, String>{};
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    if (entry.key is! String || entry.value is! String) continue;
    result[entry.key as String] = _placeholders(entry.value as String, warnings);
  }
  return result;
}

String _placeholders(String value, List<String> warnings) {
  if (value.contains('{file:')) {
    warnings.add('opencode 的 {file:...} 占位符暂不支持，已原样保留：$value');
  }
  return value.replaceAllMapped(
    RegExp(r'\{env:([A-Za-z_][A-Za-z0-9_]*)\}'),
    (Match match) => '\${${match.group(1)}}',
  );
}

String? _string(Object? raw) {
  if (raw is! String) return null;
  final String trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

void _warn(
  List<String> warnings,
  String source,
  String name,
  String message,
) {
  warnings.add('$source: mcp.servers.$name $message。');
}

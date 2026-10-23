/// `[mcp.servers.<name>]` 段的写入：同名先整体移除再追加（替换，不重复）。
library;

import 'config_toml.dart';

/// 补一段 `[mcp.servers.<name>]`，返回新内容。
///
/// 同名 server（含 `[mcp.servers.<name>.oauth]` 子表）先整体移除，因此重复
/// `nava mcp add` 是替换语义，不会写出两份同名表。`url` 非空时写 http，
/// 否则 [command]（第一个元素是可执行文件，其余是参数）与 [args] 写 stdio。
// REASON: 接口由 CLI 直接映射配置字段，参数超出常规上限但语义单一。
String appendMcpServerSection(
  String toml, {
  required String name,
  String? url,
  List<String>? command,
  List<String>? args,
  bool? oauth,
}) {
  final List<String> executable = <String>[...?command, ...?args];
  if (url == null && executable.isEmpty) {
    throw ArgumentError('MCP server 需要 url 或 command。');
  }
  final String header = '[mcp.servers.${tomlKey(name)}';
  // 手写的等价引号键（[mcp.servers."docs"]）也要一并替换，避免重复表。
  final List<String> prefixes = <String>[
    header,
    '[mcp.servers."${tomlString(name)}"',
  ];
  final StringBuffer buffer = StringBuffer(_withoutServer(toml, prefixes));
  if (buffer.isNotEmpty) {
    if (!buffer.toString().endsWith('\n')) buffer.write('\n');
    buffer.write('\n');
  }
  buffer.write('$header]\n');
  _writeEndpoint(buffer, url: url, executable: executable);
  if (oauth != null) buffer.write('oauth = $oauth\n');
  return buffer.toString();
}

void _writeEndpoint(
  StringBuffer buffer, {
  String? url,
  required List<String> executable,
}) {
  if (url != null) {
    buffer
      ..write('type = "http"\n')
      ..write('url = "${tomlString(url)}"\n');
    return;
  }
  buffer
    ..write('type = "stdio"\n')
    ..write('command = "${tomlString(executable.first)}"\n');
  if (executable.length > 1) {
    final Iterable<String> args = executable
        .skip(1)
        .map((String arg) => '"${tomlString(arg)}"');
    buffer.write('args = [ ${args.join(', ')} ]\n');
  }
}

/// 移除目标 server 的全部表（主表 + 嵌套子表），其余行原样保留。
String _withoutServer(String toml, List<String> prefixes) {
  final List<String> kept = <String>[];
  bool skipping = false;
  for (final String line in toml.split('\n')) {
    final String trimmed = line.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      skipping = _belongsToServer(trimmed, prefixes);
    }
    if (!skipping) kept.add(line);
  }
  return kept.join('\n');
}

bool _belongsToServer(String header, List<String> prefixes) {
  for (final String prefix in prefixes) {
    if (!header.startsWith(prefix) || header.length <= prefix.length) {
      continue;
    }
    final String next = header[prefix.length];
    if (next == ']' || next == '.') return true;
  }
  return false;
}

/// `[mcp.servers.<name>]` 段的写入：同名先整体移除再追加（替换，不重复）。
library;

import 'package:toml/toml.dart';

import 'config_toml.dart';

/// 补一段 `[mcp.servers.<name>]`，返回新内容。
///
/// 同名 server（含 `[mcp.servers.<name>.oauth]` 子表）先整体移除，因此重复
/// `nava mcp add` 是替换语义，不会写出两份同名表。`url` 非空时写 http，
/// 否则 [command]（第一个元素是可执行文件，其余是参数）与 [args] 写 stdio。
///
/// 结果必须能被 TOML 解析；否则抛 [FormatException]，调用方应放弃写盘。
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
  final StringBuffer buffer = StringBuffer(_withoutServer(toml, name));
  if (buffer.isNotEmpty) {
    if (!buffer.toString().endsWith('\n')) buffer.write('\n');
    buffer.write('\n');
  }
  buffer.write('$header]\n');
  _writeEndpoint(buffer, url: url, executable: executable);
  if (oauth != null) buffer.write('oauth = $oauth\n');
  final String output = buffer.toString();
  _ensureParseable(output);
  return output;
}

/// 配置里是否已有同名 server 表（用于提示替换会丢掉自定义字段）。
bool mcpServerSectionExists(String toml, String name) {
  for (final String line in toml.split('\n')) {
    final List<String>? path = _headerPath(line);
    if (path != null && _belongsToServer(path, name)) return true;
  }
  return false;
}

void _ensureParseable(String toml) {
  try {
    // toMap() 才会做重复键 / 表类型等语义校验；parse 本身是惰性的。
    TomlDocument.parse(toml).toMap();
  } on TomlException catch (error) {
    throw FormatException('写入后的配置不是合法 TOML（$error）');
  }
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
String _withoutServer(String toml, String name) {
  final List<String> kept = <String>[];
  bool skipping = false;
  for (final String line in toml.split('\n')) {
    final String trimmed = _stripComment(line).trim();
    if (trimmed.startsWith('[')) {
      final List<String>? path = _headerPath(line);
      skipping = path != null && _belongsToServer(path, name);
    }
    if (!skipping) kept.add(line);
  }
  return kept.join('\n');
}

bool _belongsToServer(List<String> path, String name) {
  if (path.length < 3) return false;
  if (path[0] != 'mcp') return false;
  if (path[1] != 'servers') return false;
  return path[2] == name;
}

/// 解析表头行：去注释、去括号内空白、支持单/双引号键。
List<String>? _headerPath(String line) {
  final String code = _stripComment(line).trim();
  if (code.length < 3) return null;
  if (!code.startsWith('[') || !code.endsWith(']')) return null;
  final String inner = code.substring(1, code.length - 1).trim();
  if (inner.isEmpty || inner.startsWith('[')) return null;
  return _splitKeyPath(inner);
}

/// 去掉引号外的 `#` 注释；引号内的 `#` 属于键名。
String _stripComment(String line) {
  String quote = '';
  for (int index = 0; index < line.length; index++) {
    final String char = line[index];
    if (quote.isNotEmpty) {
      if (char == r'\' && quote == '"') {
        index++;
      } else if (char == quote) {
        quote = '';
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
    } else if (char == '#') {
      return line.substring(0, index);
    }
  }
  return line;
}

List<String> _splitKeyPath(String text) {
  final List<String> parts = <String>[];
  final StringBuffer current = StringBuffer();
  String quote = '';
  for (int index = 0; index < text.length; index++) {
    final String char = text[index];
    if (quote.isNotEmpty) {
      current.write(char);
      if (char == r'\' && quote == '"') {
        if (index + 1 < text.length) current.write(text[++index]);
      } else if (char == quote) {
        quote = '';
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      current.write(char);
    } else if (char == '.') {
      parts.add(_decodeKey(current.toString()));
      current.clear();
    } else {
      current.write(char);
    }
  }
  parts.add(_decodeKey(current.toString()));
  return parts;
}

String _decodeKey(String raw) {
  final String key = raw.trim();
  if (key.length < 2) return key;
  if (key.startsWith('"') && key.endsWith('"')) {
    return _unescapeBasic(key.substring(1, key.length - 1));
  }
  if (key.startsWith("'") && key.endsWith("'")) {
    return key.substring(1, key.length - 1);
  }
  return key;
}

String _unescapeBasic(String text) {
  final StringBuffer buffer = StringBuffer();
  for (int index = 0; index < text.length; index++) {
    final String char = text[index];
    if (char != r'\' || index + 1 >= text.length) {
      buffer.write(char);
      continue;
    }
    final String next = text[++index];
    buffer.write(_basicEscapes[next] ?? next);
  }
  return buffer.toString();
}

const Map<String, String> _basicEscapes = <String, String>{
  'b': '\b',
  't': '\t',
  'n': '\n',
  'f': '\f',
  'r': '\r',
  '"': '"',
  r'\': r'\',
};

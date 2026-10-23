part of 'mcp_cli.dart';

Future<int> _add(List<String> args, String? configPath, McpCliDeps deps) async {
  final _AddRequest? request = _parseAdd(args, deps);
  if (request == null) return 2;
  final String path = configPath ?? resolveConfigPath();
  if (_protectedPath(path)) {
    _err(deps).writeln('拒绝写入 .opencode：nava 只写 ~/.nava/config.toml。');
    return 2;
  }
  final File file = File(path);
  final String toml = file.existsSync() ? file.readAsStringSync() : '';
  final String next;
  try {
    next = appendMcpServerSection(
      toml,
      name: request.name,
      url: request.url,
      command: request.command,
      oauth: request.oauth,
    );
  } on ArgumentError catch (error) {
    return _usageError(deps, '${error.message}');
  }
  writeFileAtomic(path, next);
  _out(deps).writeln('已写入 MCP server ${request.name} → $path');
  return 0;
}

/// REASON: 命令行选项解析天然多分支，集中在一处比嵌套辅助函数更易读。
_AddRequest? _parseAdd(List<String> args, McpCliDeps deps) {
  String? name;
  String? url;
  List<String>? command;
  bool? oauth;
  for (int index = 0; index < args.length; index++) {
    final String arg = args[index];
    if (arg == '--') {
      final List<String> rest = args.sublist(index + 1);
      if (name == null || url != null) {
        return _badAdd(deps, '-- 只能跟在名字后，且不能与 --url 同用。');
      }
      if (rest.isEmpty) return _badAdd(deps, '-- 之后缺少命令。');
      command = rest;
      break;
    }
    if (arg == '--global') continue;
    if (arg == '--oauth' || arg == '--no-oauth') {
      oauth = arg == '--oauth';
      continue;
    }
    if (arg == '--url') {
      if (index + 1 >= args.length) return _badAdd(deps, '--url 缺少地址。');
      url = args[++index];
      continue;
    }
    if (arg.startsWith('-')) return _badAdd(deps, '未知选项 $arg。');
    if (name != null) {
      return _badAdd(deps, '多余的参数 $arg（stdio 命令请写在 -- 之后）。');
    }
    name = arg;
  }
  if (name == null) return _badAdd(deps, '缺少 server 名字。');
  if (url == null && command == null) {
    return _badAdd(deps, '需要 --url <地址> 或 -- <命令...>。');
  }
  return (name: name, url: url, command: command, oauth: oauth);
}

_AddRequest? _badAdd(McpCliDeps deps, String message) {
  _err(deps).writeln('用法错误：$message\n$_usage');
  return null;
}

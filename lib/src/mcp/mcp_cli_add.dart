part of 'mcp_cli.dart';

Future<int> _add(List<String> args, String? configPath, McpCliDeps deps) async {
  final _AddRequest? request = _parseAdd(args, deps);
  if (request == null) return 2;
  try {
    return _writeAdd(request, configPath, deps);
  } on FormatException catch (error) {
    _err(deps).writeln('配置写入失败：${error.message}（原文件未改动）');
    return 2;
  } on FileSystemException catch (error) {
    _err(deps).writeln('配置读写失败：${error.message}');
    return 2;
  } on ProcessException catch (error) {
    _err(deps).writeln('配置写入失败：${error.message}');
    return 2;
  } on StateError catch (error) {
    _err(deps).writeln('配置写入失败：${error.message}');
    return 2;
  }
}

int _writeAdd(_AddRequest request, String? configPath, McpCliDeps deps) {
  final String path = configPath ?? resolveConfigPath();
  if (_protectedPath(path)) {
    _err(deps).writeln(
      '拒绝写入只读的 .opencode / ~/.config/opencode：nava 只写 ~/.nava/config.toml。',
    );
    return 2;
  }
  final File file = File(path);
  final String toml = file.existsSync() ? file.readAsStringSync() : '';
  final bool replacing = mcpServerSectionExists(toml, request.name);
  final String next = appendMcpServerSection(
    toml,
    name: request.name,
    url: request.url,
    command: request.command,
    oauth: request.oauth,
  );
  writeFileAtomic(path, next);
  _out(deps).writeln('已写入 MCP server ${request.name} → $path');
  if (replacing) {
    _err(deps).writeln(
      '注意：已替换 MCP server ${request.name} 的整段配置；'
      '原有 headers / env / oauth 等自定义字段未保留，请按需补回。',
    );
  }
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
  _usageError(deps, message);
  return null;
}

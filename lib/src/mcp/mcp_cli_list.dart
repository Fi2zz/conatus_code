part of 'mcp_cli.dart';

Future<int> _list(
  List<String> args,
  String? configPath,
  McpCliDeps deps,
) async {
  if (args.isNotEmpty) return _usageError(deps, 'list 不接受参数。');
  final String path = configPath ?? resolveConfigPath();
  final List<McpServerSpec> servers;
  try {
    servers = _loadEffectiveMcp(
      path,
      onWarning: (String message) => _err(deps).writeln(message),
      env: deps.env,
      includeClaudeDesktop: deps.includeClaudeDesktop,
    );
  } on ConfigException catch (error) {
    _err(deps).writeln('配置错误：${error.message}');
    return 2;
  }
  if (servers.isEmpty) {
    _out(deps).writeln('没有配置 MCP server。');
    return 0;
  }
  for (final McpServerSpec spec in servers) {
    _out(deps).writeln(_describeServer(spec));
  }
  return 0;
}

String _describeServer(McpServerSpec spec) {
  final List<String> command = <String>[
    if (spec.command != null) spec.command!,
    ...spec.args,
  ];
  final String target = spec.url ?? command.map(_quoteArg).join(' ');
  return '${spec.name}\t${spec.type.name}\t$target';
}

/// 带空白 / 引号 / 反斜杠的参数加引号，避免 `list` 输出无法还原命令。
String _quoteArg(String arg) {
  if (arg.isNotEmpty && !RegExp(r'''[\s"\\]''').hasMatch(arg)) return arg;
  final String escaped = arg.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

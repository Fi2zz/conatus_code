part of 'mcp_cli.dart';

Future<int> _list(
  List<String> args,
  String? configPath,
  McpCliDeps deps,
) async {
  if (args.isNotEmpty) return _usageError(deps, 'list 不接受参数。');
  final String path = configPath ?? resolveConfigPath();
  if (!File(path).existsSync()) {
    _out(deps).writeln('没有配置 MCP server。');
    return 0;
  }
  final McpConfig mcp;
  try {
    mcp = _loadMcp(path);
  } on ConfigException catch (error) {
    _err(deps).writeln('配置错误：${error.message}');
    return 2;
  }
  if (mcp.servers.isEmpty) {
    _out(deps).writeln('没有配置 MCP server。');
    return 0;
  }
  for (final McpServerSpec spec in mcp.servers) {
    _out(deps).writeln(_describeServer(spec));
  }
  return 0;
}

String _describeServer(McpServerSpec spec) {
  final String target =
      spec.url ??
      <String>[if (spec.command != null) spec.command!, ...spec.args].join(' ');
  return '${spec.name}\t${spec.type.name}\t$target';
}

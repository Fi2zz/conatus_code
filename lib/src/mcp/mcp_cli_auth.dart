part of 'mcp_cli.dart';

Future<int> _auth(
  List<String> args,
  String? configPath,
  McpCliDeps deps,
) async {
  if (args.length != 1) return _usageError(deps, 'auth 需要一个 server 名字。');
  final String name = args.first;
  final ({McpServerSpec? spec, String? error}) resolved = _findServer(
    name,
    configPath,
  );
  final McpServerSpec? spec = resolved.spec;
  if (spec == null) {
    _err(deps).writeln(resolved.error ?? '找不到 MCP server $name。');
    return 2;
  }
  final String? url = spec.url;
  if (spec.type == McpServerType.stdio || url == null) {
    _err(deps).writeln('MCP server $name 是 stdio，不需要 OAuth。');
    return 2;
  }
  final McpOAuthStore? store = _oauthStore(deps);
  if (store == null) return 2;
  final McpOAuthSession session =
      deps.session ??
      McpOAuthSession(log: (String line) => _out(deps).writeln(line));
  try {
    final McpOAuthToken token = await session.authorize(
      serverUrl: Uri.parse(url),
      config: spec.oauth ?? const McpOAuthConfig(),
      openUrl: deps.openUrl,
    );
    await store.save(spec.name, token);
    _out(
      deps,
    ).writeln('已保存 ${spec.name} 的 OAuth 令牌（${store.pathOf(spec.name)}）。');
    return 0;
  } on Object catch (error) {
    _err(deps).writeln('MCP 授权失败：$error');
    return 2;
  } finally {
    if (deps.session == null) session.close();
  }
}

Future<int> _logout(List<String> args, McpCliDeps deps) async {
  if (args.length != 1) return _usageError(deps, 'logout 需要一个 server 名字。');
  final McpOAuthStore? store = _oauthStore(deps);
  if (store == null) return 2;
  final String name = args.first;
  await store.remove(name);
  _out(deps).writeln('已删除 $name 的 OAuth 令牌（${store.pathOf(name)}）。');
  return 0;
}

/// 令牌存储；`NAVA_HOME` 指向只读目录时打印可读错误并返回 `null`（退出 2）。
McpOAuthStore? _oauthStore(McpCliDeps deps) {
  final McpOAuthStore? injected = deps.oauthStore;
  if (injected != null) return injected;
  try {
    return McpOAuthStore(resolveOAuthTokenDir(env: deps.env));
  } on StateError catch (error) {
    _err(deps).writeln('OAuth 令牌目录不可用：${error.message}');
    return null;
  }
}

McpConfig _loadMcp(String path) =>
    ConfigParser(decodeToml(File(path)), path).parse().mcp;

({McpServerSpec? spec, String? error}) _findServer(
  String name,
  String? configPath,
) {
  final String path = configPath ?? resolveConfigPath();
  if (!File(path).existsSync()) {
    return (spec: null, error: '找不到 MCP server $name（$path 不存在）。');
  }
  try {
    for (final McpServerSpec spec in _loadMcp(path).servers) {
      if (spec.name == name) return (spec: spec, error: null);
    }
    return (spec: null, error: '找不到 MCP server $name（$path）。');
  } on ConfigException catch (error) {
    return (spec: null, error: '配置错误：${error.message}');
  }
}

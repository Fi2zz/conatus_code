part of 'mcp_assembly.dart';

/// 读某台远程 server 的令牌；未启用 OAuth 返回 `null`（按无鉴权挂载）。
///
/// 启用 OAuth 但没有可用令牌时报告 `needs_auth` 并返回 `null`，由调用方跳过。
Future<McpOAuthToken?> _loadToken(
  McpServerSpec spec,
  McpOAuthStore store,
  void Function(String) report,
) async {
  if (!spec.oauthEnabled) return null;
  final McpOAuthToken? token = await store.load(spec.name);
  if (token != null) return token;
  report(
    'MCP server ${spec.name} 需要授权（needs_auth），已跳过；'
    '运行 nava mcp auth ${spec.name} 登录',
  );
  return null;
}

/// 一台 server 的 OAuth 运行时：每次请求取头，401 时刷新并落盘。
class _OAuthRuntime {
  _OAuthRuntime(this.headers, this.refresh);

  final Future<Map<String, String>> Function() headers;
  final Future<Map<String, String>> Function() refresh;
}

_OAuthRuntime _runtime(
  McpServerSpec spec,
  McpOAuthStore store,
  McpOAuthToken initial,
) => _OAuthRuntime(
  () async => _bearer(await _freshToken(spec, store, initial)),
  () async {
    final McpOAuthToken current = await store.load(spec.name) ?? initial;
    final McpOAuthToken next = await _refresh(spec, current);
    await store.save(spec.name, next);
    return _bearer(next);
  },
);

Map<String, String> _bearer(McpOAuthToken token) => <String, String>{
  'Authorization': 'Bearer ${token.accessToken}',
};

/// 提前 60 秒刷新（[McpOAuthToken.needsRefresh]）；没有 refresh_token 就交给 401。
Future<McpOAuthToken> _freshToken(
  McpServerSpec spec,
  McpOAuthStore store,
  McpOAuthToken initial,
) async {
  final McpOAuthToken current = await store.load(spec.name) ?? initial;
  if (!current.needsRefresh || current.refreshToken == null) return current;
  final McpOAuthToken next = await _refresh(spec, current);
  await store.save(spec.name, next);
  return next;
}

/// 刷新令牌；失败统一收敛成 `needs_auth`，消息只带 server 名与错误码。
Future<McpOAuthToken> _refresh(McpServerSpec spec, McpOAuthToken token) async {
  final McpOAuthSession session = McpOAuthSession();
  try {
    final McpAuthServerMetadata meta = await discoverAuthServer(
      Uri.parse(spec.url!),
      timeout: spec.oauth?.timeout ?? kMcpOAuthTimeout,
    );
    return await session.refresh(token, meta: meta, config: spec.oauth);
  } on McpException catch (error) {
    throw McpException(
      'needs_auth',
      'MCP server ${spec.name} 刷新令牌失败（${error.code}）',
    );
  } finally {
    session.close();
  }
}

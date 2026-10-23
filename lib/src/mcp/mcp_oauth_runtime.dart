/// 单台远程 MCP server 的 OAuth 运行时：取 Bearer 头、过期/401 刷新并落盘。
///
/// 令牌缓存在内存（不在每次请求时读文件）；刷新是单飞的——同一 server 并发
/// 多个 401 只发一次 `refresh_token`，避免刷新令牌轮换竞态。
library;

import 'package:conatus_mcp/conatus_mcp.dart';

import '../config/config_schema.dart';

/// 一台 server 的鉴权运行时。
class McpOAuthRuntime {
  /// 构造；[initial] 来自 `McpOAuthStore.load`。
  McpOAuthRuntime({
    required McpServerSpec spec,
    required McpOAuthStore store,
    required McpOAuthToken initial,
  }) : _spec = spec,
       _store = store,
       _token = initial;

  final McpServerSpec _spec;
  final McpOAuthStore _store;
  McpOAuthToken _token;
  Future<McpOAuthToken>? _refreshing;

  /// 每次请求前取鉴权头；快过期（60 秒内）时主动刷新。
  Future<Map<String, String>> headers() async {
    if (_token.needsRefresh && _token.refreshToken != null) {
      await _ensureRefreshed();
    }
    return _bearer(_token);
  }

  /// 401 后刷新并返回新头；失败抛 `needs_auth`。
  ///
  /// 先重读令牌文件：另一个 nava 进程可能已经刷新并轮换了令牌，这时直接用
  /// 磁盘上的新值，避免拿旧 refresh_token 再换一次（部分 AS 会判定重放并
  /// 吊销，双方都变 needs_auth）。
  Future<Map<String, String>> refresh() async {
    final McpOAuthToken? stored = await _store.load(_spec.name);
    if (stored != null && stored.accessToken != _token.accessToken) {
      _token = stored;
      return _bearer(_token);
    }
    await _ensureRefreshed();
    return _bearer(_token);
  }

  Future<McpOAuthToken> _ensureRefreshed() {
    final Future<McpOAuthToken>? pending = _refreshing;
    if (pending != null) return pending;
    final Future<McpOAuthToken> future = _refreshAndSave();
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
  }

  Future<McpOAuthToken> _refreshAndSave() async {
    final McpOAuthToken next = await _refreshToken(_spec, _token);
    await _store.save(_spec.name, next);
    _token = next;
    return next;
  }
}

Map<String, String> _bearer(McpOAuthToken token) => <String, String>{
  'Authorization': 'Bearer ${token.accessToken}',
};

/// 发现令牌端点后刷新；任何失败都收敛为 `needs_auth`（消息只带名字与码）。
Future<McpOAuthToken> _refreshToken(
  McpServerSpec spec,
  McpOAuthToken token,
) async {
  final Uri serverUrl = Uri.parse(spec.url!);
  final McpOAuthSession session = McpOAuthSession(log: (String _) {});
  try {
    final McpAuthServerMetadata meta = await discoverAuthServer(
      serverUrl,
      timeout: spec.oauth?.timeout ?? kMcpOAuthTimeout,
    );
    return await session.refresh(
      token,
      meta: meta,
      config: spec.oauth,
      resource: serverUrl,
    );
  } on McpException catch (error) {
    throw McpException(
      'needs_auth',
      'MCP server ${spec.name} 刷新令牌失败（${error.code}）',
    );
  } on Object {
    throw McpException('needs_auth', 'MCP server ${spec.name} 刷新令牌失败');
  } finally {
    session.close();
  }
}

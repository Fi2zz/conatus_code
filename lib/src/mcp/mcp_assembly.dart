/// MCP server 的装配：把 config.toml 的 `[mcp.servers.*]` 声明逐台挂进
/// `conatus_mcp` 的 [McpRegistry]；单台失败提示并跳过，不阻塞启动。
///
/// stdio 传输的子进程**不走** Layer 2 沙箱：MCP server 是用户在 config.toml
/// 显式声明的受信端，与模型临时写出的命令（`run_command`）不同风险面。
library;

import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:http/http.dart' as http;

import '../config/config_path.dart';
import '../config/config_schema.dart';
import 'mcp_oauth_runtime.dart';

/// 逐台装配 [specs] 声明的 MCP server；空列表返回 `null`（不占 `'mcp'` 键）。
///
/// 先 `provideMcp` 建注册表，再逐台 `attach`：单台握手/发现失败时经 [onError]
/// 提示并跳过（MCP server 是外部进程，不能让它拖垮启动）。`env` / `headers`
/// 里的 `${KEY}` 占位符经 [credentials] 解析；解析结果不写日志。
///
/// 远程 server 缺省尝试 OAuth：令牌从 [oauthStore]（缺省 `~/.nava/oauth`）
/// 读取；没有令牌时先按未鉴权连接，服务端真返回 401 才标记 `needs_auth` 并
/// 只跳过该台。静态 `Authorization` 头优先，不要求 OAuth（显式 `enabled = true`
/// 除外）。
///
/// [transportFactory] 是测试注入点（假传输）；[onError] 缺省写 stderr。
// REASON: 装配入口聚合（6 个参数）：测试需要注入传输、令牌目录与错误出口。
Future<McpRegistry?> attachMcpServers(
  Context app,
  List<McpServerSpec> specs, {
  Credentials? credentials,
  McpTransport Function(McpServerConfig config)? transportFactory,
  void Function(String message)? onError,
  McpOAuthStore? oauthStore,
}) async {
  if (specs.isEmpty) return null;
  final McpRegistry registry = await provideMcp(app, const <McpServerConfig>[]);
  final void Function(String) report = onError ?? stderr.writeln;
  final McpOAuthStore store =
      oauthStore ?? McpOAuthStore(resolveOAuthTokenDir());
  for (final McpServerSpec spec in specs) {
    try {
      final McpServerConfig config = toMcpServerConfig(spec, credentials);
      reportUnresolvedPlaceholders(spec.name, config, report);
      final McpOAuthToken? token = await _loadToken(spec, store);
      final McpOAuthRuntime? auth = token == null
          ? null
          : McpOAuthRuntime(spec: spec, store: store, initial: token);
      final McpClient client = McpClient(
        transport:
            transportFactory?.call(config) ??
            toMcpTransport(
              config,
              authHeaders: auth?.headers,
              refreshAuth: auth?.refresh,
            ),
        serverName: config.name,
      );
      await registry.attach(app, client);
    } on McpException catch (error) {
      _reportFailure(spec.name, error, report);
    } catch (error) {
      // 收敛整段：配置转换 / 传输构造 / 握手中任一抛错都只跳过这一台，
      // 不中断其余 server 的装配（此前只包住 attach，程序化调用会整循环中断）。
      report('MCP server ${spec.name} 连接失败，已跳过：$error');
    }
  }
  return registry;
}

/// 401 / 缺少令牌：提示用 CLI 登录；其他异常走通用失败提示。
void _reportFailure(
  String server,
  McpException error,
  void Function(String) report,
) {
  if (error.code == 'needs_auth') {
    report(
      'MCP server $server 需要授权（needs_auth），已跳过；'
      '运行 nava mcp auth $server 登录',
    );
    return;
  }
  report('MCP server $server 连接失败，已跳过：$error');
}

/// 读某台 server 的令牌；未启用 OAuth、或静态 `Authorization` 头优先时返回
/// `null`（按无鉴权 / 静态头挂载）。
Future<McpOAuthToken?> _loadToken(
  McpServerSpec spec,
  McpOAuthStore store,
) async {
  if (!_oauthActive(spec)) return null;
  return store.load(spec.name);
}

/// 该 server 是否走 OAuth。
///
/// 静态 `Authorization` 头意味着用户已自行配置鉴权：除非显式
/// `[mcp.servers.x.oauth] enabled = true`，否则不要求令牌。公开 server 不做
/// 预判——先按无鉴权连接，真返回 401 才标 `needs_auth`。
bool _oauthActive(McpServerSpec spec) {
  if (!spec.oauthEnabled) return false;
  if (spec.oauth?.enabled == true) return true;
  return !_hasAuthorizationHeader(spec.headers);
}

bool _hasAuthorizationHeader(Map<String, String> headers) {
  for (final String key in headers.keys) {
    if (key.toLowerCase() == 'authorization') return true;
  }
  return false;
}

/// 报告 [config] 的 `env` / `headers` 里仍以 `${KEY}` 形式存在的未解析占位符。
///
/// 只报「哪个键的哪个占位符名」——**绝不打印值**（值可能含明文凭据）。解析失败
/// 会被原样下发，通常以 401 收场；此前完全静默，排障只能从 401 倒推（E-18）。
void reportUnresolvedPlaceholders(
  String server,
  McpServerConfig config,
  void Function(String message) report,
) {
  final Map<String, Map<String, String>> sections =
      <String, Map<String, String>>{
        'env': config.env,
        'headers': config.headers,
      };
  for (final MapEntry<String, Map<String, String>> section
      in sections.entries) {
    for (final MapEntry<String, String> item in section.value.entries) {
      for (final RegExpMatch match in _placeholderPattern.allMatches(
        item.value,
      )) {
        report(
          'MCP server $server：${section.key} 键 ${item.key} 的占位符 '
          '\${${match.group(1)}} 未解析（原样下发，通常导致鉴权失败）',
        );
      }
    }
  }
}

/// `${KEY}` 占位符识别；只用来找「没被替换掉」的键名，不解析值。
final RegExp _placeholderPattern = RegExp(r'\$\{([^}]+)\}');

/// 把 config 层的 [McpServerSpec] 映射为 `conatus_mcp` 的 [McpServerConfig]，
/// 并解析 `env` / `headers` 里的 `${KEY}` 占位符（解析不了的键原样保留）。
///
/// 返回值的 `env` / `headers` 可能含明文凭据：不得写进日志或会话事件。
McpServerConfig toMcpServerConfig(
  McpServerSpec spec,
  Credentials? credentials,
) => McpServerConfig(
  name: spec.name,
  type: switch (spec.type) {
    McpServerType.stdio => McpTransportType.stdio,
    McpServerType.http => McpTransportType.http,
    McpServerType.sse => McpTransportType.sse,
  },
  command: spec.command,
  args: spec.args,
  env: resolveCredentialPlaceholders(spec.env, credentials),
  url: spec.url,
  headers: resolveCredentialPlaceholders(spec.headers, credentials),
);

/// 按传输类型分派默认传输实现（与 `provideMcp` 的内部分派一致）。
///
/// [authHeaders] / [refreshAuth] 只对 HTTP 系传输生效（stdio 忽略）。
McpTransport toMcpTransport(
  McpServerConfig config, {
  Future<Map<String, String>> Function()? authHeaders,
  Future<Map<String, String>> Function()? refreshAuth,
  http.Client? client,
}) => switch (config.type) {
  McpTransportType.stdio => StdioTransport(
    command: config.command!,
    args: config.args,
    env: config.env,
  ),
  McpTransportType.http => HttpTransport(
    url: config.url!,
    headers: config.headers,
    authHeaders: authHeaders,
    refreshAuth: refreshAuth,
    client: client,
  ),
  McpTransportType.sse => SseTransport(
    url: config.url!,
    headers: config.headers,
    authHeaders: authHeaders,
    refreshAuth: refreshAuth,
    client: client,
  ),
};

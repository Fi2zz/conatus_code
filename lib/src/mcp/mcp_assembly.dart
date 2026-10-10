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

import '../config/config_schema.dart';

/// 逐台装配 [specs] 声明的 MCP server；空列表返回 `null`（不占 `'mcp'` 键）。
///
/// 先 `provideMcp` 建注册表，再逐台 `attach`：单台握手/发现失败时经 [onError]
/// 提示并跳过（MCP server 是外部进程，不能让它拖垮启动）。`env` / `headers`
/// 里的 `${KEY}` 占位符经 [credentials] 解析；解析结果不写日志。
///
/// [transportFactory] 是测试注入点（假传输）；[onError] 缺省写 stderr。
// REASON: 装配入口聚合（5 个参数）：测试需要注入传输与错误出口，拆对象反而绕。
Future<McpRegistry?> attachMcpServers(
  Context app,
  List<McpServerSpec> specs, {
  Credentials? credentials,
  McpTransport Function(McpServerConfig config)? transportFactory,
  void Function(String message)? onError,
}) async {
  if (specs.isEmpty) return null;
  final McpRegistry registry = await provideMcp(app, const <McpServerConfig>[]);
  final void Function(String) report = onError ?? stderr.writeln;
  for (final McpServerSpec spec in specs) {
    try {
      final McpServerConfig config = toMcpServerConfig(spec, credentials);
      reportUnresolvedPlaceholders(spec.name, config, report);
      final McpClient client = McpClient(
        transport: transportFactory?.call(config) ?? toMcpTransport(config),
        serverName: config.name,
      );
      await registry.attach(app, client);
    } catch (error) {
      // 收敛整段：配置转换 / 传输构造 / 握手中任一抛错都只跳过这一台，
      // 不中断其余 server 的装配（此前只包住 attach，程序化调用会整循环中断）。
      report('MCP server ${spec.name} 连接失败，已跳过：$error');
    }
  }
  return registry;
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
  final Map<String, Map<String, String>> sections = <String, Map<String, String>>{
    'env': config.env,
    'headers': config.headers,
  };
  for (final MapEntry<String, Map<String, String>> section
      in sections.entries) {
    for (final MapEntry<String, String> item in section.value.entries) {
      for (final RegExpMatch match
          in _placeholderPattern.allMatches(item.value)) {
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
) =>
    McpServerConfig(
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
McpTransport toMcpTransport(McpServerConfig config) => switch (config.type) {
      McpTransportType.stdio => StdioTransport(
          command: config.command!, args: config.args, env: config.env),
      McpTransportType.http =>
        HttpTransport(url: config.url!, headers: config.headers),
      McpTransportType.sse =>
        SseTransport(url: config.url!, headers: config.headers),
    };

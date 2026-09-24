/// 测试共用的进程内假 MCP 传输（复制 conatus_mcp 测试助手的最小形态）。
library;

import 'dart:async';

import 'package:conatus_mcp/conatus_mcp.dart';

/// 双向假传输：记录 [sent]、可回灌消息、可模拟对端关闭或连接失败。
class FakeMcpTransport implements McpTransport {
  final StreamController<McpMessage> _incoming = StreamController<McpMessage>();

  /// 已发出的全部消息（含通知）。
  final List<McpMessage> sent = <McpMessage>[];

  /// 收到消息时的钩子；用它做自动应答或断言。
  Future<void> Function(McpMessage message)? onSend;

  /// 非空时 [connect] 抛它，模拟连不上的服务端。
  Object? connectError;

  @override
  Stream<McpMessage> get messages => _incoming.stream;

  @override
  Stream<String> get diagnostics => const Stream<String>.empty();

  @override
  Future<void> connect() async {
    final Object? error = connectError;
    if (error != null) throw error;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> send(McpMessage message) async {
    sent.add(message);
    final Future<void> Function(McpMessage message)? handler = onSend;
    if (handler != null) await handler(message);
  }

  /// 回灌一条消息。
  void emit(McpMessage message) => _incoming.add(message);

  /// 结束消息流（模拟对端关闭）。
  Future<void> finish() => _incoming.close();
}

/// 装上自动应答钩子：按方法名回 `result`，并按请求 id 回灌响应。
void autoRespond(
  FakeMcpTransport transport,
  Map<String, Object?>? Function(String method, Map<String, Object?>? params)
      reply,
) {
  transport.onSend = (McpMessage message) async {
    final Object? id = message.id;
    final String? method = message.method;
    if (id == null || method == null) return;
    final Map<String, Object?>? result = reply(method, message.params);
    if (result == null) return;
    transport.emit(McpMessage(id: id, result: result));
  };
}

/// 按 server 名造假 server：握手 + tools/list 自动应答。
class FakeMcpServers {
  final Map<String, FakeMcpTransport> transports = <String, FakeMcpTransport>{};
  final Map<String, McpServerConfig> configs = <String, McpServerConfig>{};

  FakeMcpTransport build(McpServerConfig config) {
    configs[config.name] = config;
    final FakeMcpTransport transport = FakeMcpTransport();
    transports[config.name] = transport;
    autoRespond(transport, (String method, Map<String, Object?>? params) {
      if (method == 'initialize') {
        return <String, Object?>{
          'protocolVersion': kMcpProtocolVersion,
          'serverInfo': <String, Object?>{'name': config.name},
        };
      }
      if (method == 'tools/list') {
        return <String, Object?>{
          'tools': <Object?>[
            <String, Object?>{
              'name': 'read_file',
              'description': '${config.name} 的 read_file',
            },
          ],
        };
      }
      return <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': '${config.name}:ok'},
        ],
      };
    });
    return transport;
  }
}

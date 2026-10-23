/// 测试用 prompt server：声明 `prompts` 能力、两张位置参数、role/text 两条消息。
library;

import 'package:conatus_mcp/conatus_mcp.dart';

import 'fake_mcp_transport.dart';

/// 造一台支持（或不声明）prompts 的假 server。
///
/// [log] 记录收到的方法名，用来断言「没能力的 server 不发 prompts/list」。
FakeMcpTransport fakePromptServer(
  String name, {
  bool prompts = true,
  List<String>? log,
}) {
  final FakeMcpTransport transport = FakeMcpTransport();
  transport.onSend = (McpMessage message) async {
    final Object? id = message.id;
    final String? method = message.method;
    if (id == null || method == null) return;
    log?.add(method);
    transport.emit(
      McpMessage(id: id, result: _reply(name, method, prompts, message.params)),
    );
  };
  return transport;
}

Map<String, Object?> _reply(
  String name,
  String method,
  bool prompts,
  Map<String, Object?>? params,
) {
  switch (method) {
    case 'initialize':
      return <String, Object?>{
        'protocolVersion': kMcpProtocolVersion,
        'capabilities': <String, Object?>{
          if (prompts) 'prompts': <String, Object?>{},
        },
        'serverInfo': <String, Object?>{'name': name},
      };
    case 'prompts/list':
      return <String, Object?>{
        'prompts': <Object?>[
          <String, Object?>{
            'name': 'review',
            'description': '审查代码',
            'arguments': <Object?>[
              <String, Object?>{'name': 'path'},
              <String, Object?>{'name': 'depth'},
            ],
          },
        ],
      };
    case 'prompts/get':
      final String path = _arg(params, 'path');
      final String depth = _arg(params, 'depth');
      return <String, Object?>{
        'messages': <Object?>[
          <String, Object?>{
            'role': 'user',
            'content': <String, Object?>{
              'type': 'text',
              'text': 'path=$path;depth=$depth',
            },
          },
          <String, Object?>{
            'role': 'assistant',
            'content': <String, Object?>{'type': 'text', 'text': '看到 $path'},
          },
        ],
      };
  }
  return <String, Object?>{'tools': <Object?>[]};
}

String _arg(Map<String, Object?>? params, String key) {
  final Object? arguments = params?['arguments'];
  return arguments is Map<String, Object?> ? '${arguments[key] ?? ''}' : '';
}

/// 一台 docs server 的 `[mcp.servers.docs]` 声明。
McpServerConfig docsServerConfig() =>
    McpServerConfig(name: 'docs', type: McpTransportType.stdio, command: 'x');

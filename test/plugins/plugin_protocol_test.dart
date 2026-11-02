/// JSON-RPC 编解码。
library;

import 'dart:convert';

import 'package:conatus_code/src/plugins/plugin_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('请求 / 响应 / 通知可往返', () {
    final String request = PluginRpcCodec.request(1, 'init', <String, Object?>{
      'directory': '/tmp',
    });
    final PluginRpcMessage decoded = PluginRpcMessage.decode(request)!;
    expect(decoded.isRequest, isTrue);
    expect(decoded.method, 'init');
    expect(decoded.params['directory'], '/tmp');

    final String response = PluginRpcCodec.result(1, <String, Object?>{
      'ok': true,
    });
    final PluginRpcMessage result = PluginRpcMessage.decode(response)!;
    expect(result.isResponse, isTrue);
    expect(result.result['ok'], isTrue);

    final String notification = PluginRpcCodec.notification(
      'event',
      <String, Object?>{'type': 'session.idle'},
    );
    final PluginRpcMessage event = PluginRpcMessage.decode(notification)!;
    expect(event.isNotification, isTrue);
    expect(event.params['type'], 'session.idle');
  });

  test('错误对象归一成字符串', () {
    final PluginRpcMessage message = PluginRpcMessage.decode(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'error': <String, Object?>{'code': -1, 'message': 'boom'},
      }),
    )!;
    expect(message.error, 'boom');
  });

  test('非法行返回 null', () {
    expect(PluginRpcMessage.decode('not json'), isNull);
    expect(PluginRpcMessage.decode('[]'), isNull);
    expect(PluginRpcMessage.decode(''), isNull);
  });
}

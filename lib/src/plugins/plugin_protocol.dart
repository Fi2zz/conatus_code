/// 插件宿主的 JSON-RPC 2.0 编解码（一行一条消息）。
library;

import 'dart:convert';

/// 解码后的一条消息。
class PluginRpcMessage {
  const PluginRpcMessage({
    this.id,
    this.method,
    this.params = const <String, Object?>{},
    this.result = const <String, Object?>{},
    this.error,
  });

  final Object? id;
  final String? method;
  final Map<String, Object?> params;
  final Map<String, Object?> result;
  final String? error;

  bool get isRequest => method != null && id != null;
  bool get isNotification => method != null && id == null;
  bool get isResponse => method == null && id != null;

  /// 从一行 JSON 解码；格式非法返回 `null`。
  static PluginRpcMessage? decode(String line) {
    if (line.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final Map<String, Object?> json = decoded.cast<String, Object?>();
    final Object? error = json['error'];
    String? message;
    if (error is String) {
      message = error;
    } else if (error is Map) {
      message = '${error['message'] ?? error}';
    } else if (error != null) {
      message = '$error';
    }
    final Object? rawParams = json['params'];
    final Object? rawResult = json['result'];
    return PluginRpcMessage(
      id: json['id'],
      method: json['method'] as String?,
      params: rawParams is Map
          ? rawParams.cast<String, Object?>()
          : const <String, Object?>{},
      result: rawResult is Map
          ? rawResult.cast<String, Object?>()
          : const <String, Object?>{},
      error: message,
    );
  }

  /// 面向日志的简短描述。
  String describe() => 'PluginRpcMessage(${method ?? 'response'}#$id)';
}

/// 请求 / 通知 / 响应的编码。
class PluginRpcCodec {
  const PluginRpcCodec._();

  static String request(
    Object id,
    String method,
    Map<String, Object?> params,
  ) => jsonEncode(<String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  });

  static String notification(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) => jsonEncode(<String, Object?>{
    'jsonrpc': '2.0',
    'method': method,
    'params': params,
  });

  static String result(Object id, Map<String, Object?> value) => jsonEncode(
    <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': value},
  );

  static String error(Object id, String message) =>
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': -32000, 'message': message},
      });
}

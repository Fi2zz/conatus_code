/// 自定义工具的输出协议：`{"content"}` / `{"error"}` / 纯文本。
library;

import 'dart:convert';

import 'package:conatus_foundation/conatus_foundation.dart';

/// 解析 CLI stdout 或 HTTP 响应体。
ToolResult parseCustomToolOutput(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) return ToolResult.success('');
  try {
    final Object? decoded = jsonDecode(text);
    if (decoded is Map) {
      final Object? content = decoded['content'];
      if (content is String) return ToolResult.success(content);
      final Object? error = decoded['error'];
      if (error is String) return customToolFailure(error, 'TOOL_ERROR');
      if (error is Map && error['message'] is String) {
        return customToolFailure(
          error['message'] as String,
          error['code'] is String ? error['code'] as String : 'TOOL_ERROR',
        );
      }
      if (decoded['value'] != null) {
        return ToolResult.success(text, value: decoded['value']);
      }
    }
    return ToolResult.success(text);
  } on FormatException {
    return ToolResult.success(text);
  }
}

/// 统一失败结果。
ToolResult customToolFailure(String message, String code) =>
    ToolResult.failure(message, error: ToolError(code, message));

/// 错误展示最多 2000 字符（完整内容仍可从进程/HTTP 输出取回）。
String clipCustomToolText(String text) =>
    text.length <= 2000 ? text : '${text.substring(0, 2000)}…';

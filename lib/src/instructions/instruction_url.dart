/// `instructions` 的 URL 来源：5 秒超时、失败跳过、单文件截断。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'instruction_types.dart';

/// UTF-8 单字符最多 4 字节；按上限的 4 倍收集即可覆盖截断点，避免整包下载。
const int _kMaxBytes = kInstructionMaxChars * 4;

/// 拉取一条 URL 指令；不可达、非 2xx、空内容都返回 `null`。
Future<InstructionDoc?> fetchInstructionUrl(String url) async {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null) return null;
  final HttpClient client = HttpClient()
    ..connectionTimeout = kInstructionUrlTimeout;
  try {
    final HttpClientResponse response = await client
        .getUrl(uri)
        .then((HttpClientRequest request) => request.close())
        .timeout(kInstructionUrlTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final List<int> bytes = await _readCapped(response);
    final String text = utf8.decode(bytes, allowMalformed: true);
    if (text.trim().isEmpty) return null;
    return InstructionDoc(identity: url, text: capInstructionText(text));
  } on Exception {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// 收集到单文件上限即停；解码在收集完成后一次进行，避免多字节字符被
/// chunk 边界切开。
Future<List<int>> _readCapped(HttpClientResponse response) async {
  final List<int> bytes = <int>[];
  await for (final List<int> chunk in response.timeout(
    kInstructionUrlTimeout,
  )) {
    bytes.addAll(chunk);
    if (bytes.length >= _kMaxBytes) break;
  }
  return bytes;
}

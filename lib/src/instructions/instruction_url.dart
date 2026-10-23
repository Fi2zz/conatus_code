/// `instructions` 的 URL 来源：5 秒超时、失败跳过、单文件截断。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'instruction_source.dart'
    show
        InstructionDoc,
        capInstructionText,
        kInstructionMaxChars,
        kInstructionUrlTimeout;

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
    final String text = await _readCapped(response);
    if (text.trim().isEmpty) return null;
    return InstructionDoc(identity: url, text: capInstructionText(text));
  } on Exception {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// 读到单文件上限即停，避免一个大文件把内存吃满。
Future<String> _readCapped(HttpClientResponse response) async {
  final StringBuffer buffer = StringBuffer();
  await for (final List<int> chunk in response.timeout(
    kInstructionUrlTimeout,
  )) {
    buffer.write(utf8.decode(chunk, allowMalformed: true));
    if (buffer.length >= kInstructionMaxChars) break;
  }
  return buffer.toString();
}

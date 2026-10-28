/// LSP Content-Length 帧解析。
library;

import 'dart:convert';

/// 把 stdout 的任意分片累积成完整 JSON-RPC 消息；坏帧直接丢弃。
class LspFrameReader {
  final List<int> _buffer = <int>[];

  List<Map<String, dynamic>> add(List<int> bytes) {
    _buffer.addAll(bytes);
    final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[];
    while (true) {
      final int headerEnd = _headerEnd();
      if (headerEnd < 0) break;
      final String header = utf8.decode(
        _buffer.sublist(0, headerEnd),
        allowMalformed: true,
      );
      final Match? match = RegExp(
        r'Content-Length:\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(header);
      final int? length = match == null ? null : int.tryParse(match.group(1)!);
      if (length == null || length > 10 * 1024 * 1024) {
        _buffer.removeRange(0, headerEnd + 4);
        continue;
      }
      final int start = headerEnd + 4;
      if (_buffer.length < start + length) break;
      final List<int> body = _buffer.sublist(start, start + length);
      _buffer.removeRange(0, start + length);
      try {
        final Object? decoded = jsonDecode(utf8.decode(body));
        if (decoded is Map<String, dynamic>) messages.add(decoded);
      } catch (_) {
        // Ignore malformed JSON; next frame can still be parsed.
      }
    }
    return messages;
  }

  void reset() => _buffer.clear();

  int _headerEnd() {
    for (int index = 0; index + 3 < _buffer.length; index++) {
      if (_buffer[index] == 13 &&
          _buffer[index + 1] == 10 &&
          _buffer[index + 2] == 13 &&
          _buffer[index + 3] == 10) {
        return index;
      }
    }
    return -1;
  }
}

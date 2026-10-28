/// 测试用 LSP server：initialize + 每个文档发一条 fake diagnostic。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final String? marker = _arg(args, '--marker');
  if (marker != null) {
    File(marker).writeAsStringSync('started\n', mode: FileMode.append);
  }
  if (args.contains('--crash')) exit(1);
  if (args.contains('--hang')) {
    await Future<void>.delayed(const Duration(hours: 1));
    return;
  }
  final bool ignoreShutdown = args.contains('--ignore-shutdown');
  final List<int> buffer = <int>[];
  await for (final List<int> chunk in stdin) {
    buffer.addAll(chunk);
    while (true) {
      final int headerEnd = _headerEnd(buffer);
      if (headerEnd < 0) break;
      final String header = utf8.decode(buffer.sublist(0, headerEnd));
      final Match? match = RegExp(r'Content-Length:\s*(\d+)').firstMatch(header);
      if (match == null) {
        buffer.removeRange(0, headerEnd + 4);
        continue;
      }
      final int length = int.parse(match.group(1)!);
      final int start = headerEnd + 4;
      if (buffer.length < start + length) break;
      final String body = utf8.decode(buffer.sublist(start, start + length));
      buffer.removeRange(0, start + length);
      final Map<String, dynamic> message =
          jsonDecode(body) as Map<String, dynamic>;
      await _handle(message, ignoreShutdown: ignoreShutdown);
    }
  }
}

Future<void> _handle(
  Map<String, dynamic> message, {
  required bool ignoreShutdown,
}) async {
  final Object? id = message['id'];
  final String? method = message['method'] as String?;
  if (method == 'initialize' && id != null) {
    _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{'capabilities': <String, Object?>{}},
    });
    return;
  }
  if (method == 'workspace/configuration' && id != null) {
    _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <Object?>[null],
    });
    return;
  }
  if (method == 'shutdown' && id != null) {
    if (ignoreShutdown) return;
    _send(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': null});
    return;
  }
  if (method == 'exit') {
    exit(0);
  }
  if (method == 'textDocument/didOpen' || method == 'textDocument/didChange') {
    final Map<String, dynamic> params =
        (message['params'] as Map).cast<String, dynamic>();
    final Map<String, dynamic> document =
        (params['textDocument'] as Map).cast<String, dynamic>();
    final String uri = document['uri'] as String;
    _send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': 'textDocument/publishDiagnostics',
      'params': <String, Object?>{
        'uri': uri,
        'diagnostics': <Map<String, Object?>>[
          <String, Object?>{
            'range': <String, Object?>{
              'start': <String, Object?>{'line': 0, 'character': 0},
              'end': <String, Object?>{'line': 0, 'character': 1},
            },
            'severity': 1,
            'code': 'fake',
            'message': 'fake diagnostic',
          },
        ],
      },
    });
  }
}

void _send(Map<String, Object?> message) {
  final List<int> body = utf8.encode(jsonEncode(message));
  stdout.add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
  stdout.add(body);
  stdout.flush();
}

int _headerEnd(List<int> buffer) {
  for (int index = 0; index + 3 < buffer.length; index++) {
    if (buffer[index] == 13 &&
        buffer[index + 1] == 10 &&
        buffer[index + 2] == 13 &&
        buffer[index + 3] == 10) {
      return index;
    }
  }
  return -1;
}

String? _arg(List<String> args, String name) {
  final int index = args.indexOf(name);
  return index >= 0 && index + 1 < args.length ? args[index + 1] : null;
}

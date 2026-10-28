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
  final bool crashAfterOpen = args.contains('--crash-after-open');
  final bool openOnly = args.contains('--open-only');
  final bool malformed = args.contains('--malformed-frames');
  final bool weirdSeverity = args.contains('--weird-severity');
  final bool stringIds = args.contains('--string-ids');
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
      await _handle(
        message,
        ignoreShutdown: ignoreShutdown,
        crashAfterOpen: crashAfterOpen,
        openOnly: openOnly,
        malformed: malformed,
        weirdSeverity: weirdSeverity,
        stringIds: stringIds,
      );
    }
  }
}

Future<void> _handle(
  Map<String, dynamic> message, {
  required bool ignoreShutdown,
  required bool crashAfterOpen,
  required bool openOnly,
  required bool malformed,
  required bool weirdSeverity,
  required bool stringIds,
}) async {
  final Object? id = message['id'];
  final String? method = message['method'] as String?;
  if (method == 'initialize' && id != null) {
    await _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': stringIds ? '$id' : id,
      'result': <String, Object?>{'capabilities': <String, Object?>{}},
    });
    return;
  }
  if (method == 'workspace/configuration' && id != null) {
    await _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': stringIds ? '$id' : id,
      'result': <Object?>[null],
    });
    return;
  }
  if (method == 'shutdown' && id != null) {
    if (ignoreShutdown) return;
    await _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': stringIds ? '$id' : id,
      'result': null,
    });
    return;
  }
  if (method == 'exit') {
    exit(0);
  }
  if (method == 'textDocument/hover' && id != null) {
    await _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{
        'contents': <String, Object?>{
          'kind': 'markdown',
          'value': 'fake hover',
        },
      },
    });
    return;
  }
  if (method == 'textDocument/definition' && id != null) {
    final Map<String, dynamic> params =
        (message['params'] as Map).cast<String, dynamic>();
    final Map<String, dynamic> document =
        (params['textDocument'] as Map).cast<String, dynamic>();
    await _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <Map<String, Object?>>[
        <String, Object?>{
          'uri': document['uri'],
          'range': <String, Object?>{
            'start': <String, Object?>{'line': 2, 'character': 3},
            'end': <String, Object?>{'line': 2, 'character': 5},
          },
        },
      ],
    });
    return;
  }
  if (method == 'textDocument/references' && id != null) {
    final Map<String, dynamic> params =
        (message['params'] as Map).cast<String, dynamic>();
    final Map<String, dynamic> document =
        (params['textDocument'] as Map).cast<String, dynamic>();
    await _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <Map<String, Object?>>[
        <String, Object?>{
          'uri': document['uri'],
          'range': <String, Object?>{
            'start': <String, Object?>{'line': 1, 'character': 2},
            'end': <String, Object?>{'line': 1, 'character': 3},
          },
        },
      ],
    });
    return;
  }
  if (method == 'textDocument/documentSymbol' && id != null) {
    await _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <Map<String, Object?>>[
        <String, Object?>{
          'name': 'fakeSymbol',
          'kind': 12,
          'range': <String, Object?>{
            'start': <String, Object?>{'line': 4, 'character': 1},
            'end': <String, Object?>{'line': 4, 'character': 2},
          },
        },
      ],
    });
    return;
  }
  if (method == 'textDocument/didOpen' || method == 'textDocument/didChange') {
    if (openOnly && method == 'textDocument/didChange') return;
    final Map<String, dynamic> params =
        (message['params'] as Map).cast<String, dynamic>();
    final Map<String, dynamic> document =
        (params['textDocument'] as Map).cast<String, dynamic>();
    final String uri = document['uri'] as String;
    if (malformed) {
      stdout.add(utf8.encode('Content-Length: nope\r\n\r\n'));
      await stdout.flush();
    }
    await _send(<String, Object?>{
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
            'severity': weirdSeverity ? 1.0 : 1,
            'code': 'fake',
            'message': 'fake diagnostic',
          },
        ],
      },
    });
    if (crashAfterOpen) exit(0);
  }
}

Future<void> _send(Map<String, Object?> message) async {
  final List<int> body = utf8.encode(jsonEncode(message));
  stdout.add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
  stdout.add(body);
  await stdout.flush();
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

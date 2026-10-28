/// 最小 LSP stdio 客户端：initialize / didOpen / didChange / diagnostics。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lsp_types.dart';

/// LSP 启动或协议失败。
class LspException implements Exception {
  const LspException(this.message);

  final String message;

  @override
  String toString() => 'LspException: $message';
}

/// 一个按需启动的 LSP server 客户端。
class LspClient {
  LspClient({
    required List<String> command,
    required String workdir,
    Map<String, String> env = const <String, String>{},
    Map<String, Object?> initialization = const <String, Object?>{},
    this.startTimeout = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 10),
    this.diagnosticsWait = const Duration(seconds: 2),
  })  : _command = command,
        _workdir = workdir,
        _env = env,
        _initialization = initialization;

  final List<String> _command;
  final String _workdir;
  final Map<String, String> _env;
  final Map<String, Object?> _initialization;
  final Duration startTimeout;
  final Duration requestTimeout;
  final Duration diagnosticsWait;

  Process? _process;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  final List<int> _buffer = <int>[];
  final Map<int, Completer<Map<String, dynamic>>> _pending =
      <int, Completer<Map<String, dynamic>>>{};
  final Map<String, List<LspDiagnostic>> _diagnostics =
      <String, List<LspDiagnostic>>{};
  final Map<String, Completer<List<LspDiagnostic>>> _waiters =
      <String, Completer<List<LspDiagnostic>>>{};
  final Map<String, int> _versions = <String, int>{};
  final Set<String> _opened = <String>{};
  int _nextId = 1;
  String _stderr = '';
  bool _started = false;
  bool _stopping = false;

  bool get running => _process != null && !_stopping;

  Future<void> start() async {
    if (_started) return;
    if (_command.isEmpty) throw const LspException('empty command');
    try {
      final Process process = await Process.start(
        _command.first,
        _command.skip(1).toList(growable: false),
        workingDirectory: _workdir,
        environment: <String, String>{...Platform.environment, ..._env},
      );
      _process = process;
      _stdoutSub = process.stdout.listen(_onStdout);
      _stderrSub = process.stderr.listen((List<int> bytes) {
        if (_stderr.length < 8000) {
          _stderr += utf8.decode(bytes, allowMalformed: true);
          if (_stderr.length > 8000) _stderr = _stderr.substring(0, 8000);
        }
      });
      unawaited(process.exitCode.then((int _) => _onExit()));
      await _initialize();
      _started = true;
    } catch (error) {
      await stop();
      if (error is LspException) rethrow;
      throw LspException('$error');
    }
  }

  Future<void> _initialize() async {
    await _request(
      'initialize',
      <String, Object?>{
        'processId': pid,
        'rootUri': Uri.file(_workdir).toString(),
        'workspaceFolders': <Map<String, Object?>>[
          <String, Object?>{
            'uri': Uri.file(_workdir).toString(),
            'name': _workdir.split(Platform.pathSeparator).last,
          },
        ],
        'capabilities': <String, Object?>{},
        'initializationOptions': _initialization,
      },
      timeout: startTimeout,
    );
    _notify('initialized', <String, Object?>{});
  }

  Future<List<LspDiagnostic>> diagnose(
    String path, {
    String? text,
    bool save = false,
  }) async {
    if (!_started) await start();
    final String uri = Uri.file(path).toString();
    final String content = text ?? await File(path).readAsString();
    final Completer<List<LspDiagnostic>> waiter =
        Completer<List<LspDiagnostic>>();
    _waiters[uri] = waiter;
    _diagnostics[uri] = const <LspDiagnostic>[];
    final int version = (_versions[uri] ?? 0) + 1;
    _versions[uri] = version;
    if (!_opened.contains(uri)) {
      _opened.add(uri);
      _notify('textDocument/didOpen', <String, Object?>{
        'textDocument': <String, Object?>{
          'uri': uri,
          'languageId': _languageId(path),
          'version': version,
          'text': content,
        },
      });
    } else {
      _notify('textDocument/didChange', <String, Object?>{
        'textDocument': <String, Object?>{'uri': uri, 'version': version},
        'contentChanges': <Map<String, Object?>>[
          <String, Object?>{'text': content},
        ],
      });
      if (save) {
        _notify('textDocument/didSave', <String, Object?>{
          'textDocument': <String, Object?>{'uri': uri},
          'text': content,
        });
      }
    }
    try {
      return await waiter.future.timeout(diagnosticsWait);
    } on TimeoutException {
      return _diagnostics[uri] ?? const <LspDiagnostic>[];
    } finally {
      _waiters.remove(uri);
    }
  }

  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    final Process? process = _process;
    if (process != null) {
      try {
        await _request('shutdown', null, timeout: const Duration(seconds: 1));
        _notify('exit', null);
      } catch (_) {
        // Server may already be gone.
      }
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process = null;
    _started = false;
    for (final Completer<Map<String, dynamic>> pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(const LspException('client stopped'));
      }
    }
    _pending.clear();
    for (final Completer<List<LspDiagnostic>> waiter in _waiters.values) {
      if (!waiter.isCompleted) waiter.complete(const <LspDiagnostic>[]);
    }
    _waiters.clear();
    _stopping = false;
  }

  Future<void> close() => stop();

  Future<Map<String, dynamic>> _request(
    String method,
    Object? params, {
    Duration? timeout,
  }) {
    final int id = _nextId++;
    final Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    return completer.future.timeout(
      timeout ?? requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw LspException('$method timed out');
      },
    );
  }

  void _notify(String method, Object? params) {
    _send(<String, Object?>{'jsonrpc': '2.0', 'method': method, 'params': params});
  }

  void _send(Map<String, Object?> message) {
    final Process? process = _process;
    if (process == null) return;
    final List<int> body = utf8.encode(jsonEncode(message));
    process.stdin.add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
    process.stdin.add(body);
  }

  void _onStdout(List<int> bytes) {
    _buffer.addAll(bytes);
    while (true) {
      final int headerEnd = _indexOfHeaderEnd();
      if (headerEnd < 0) return;
      final String header = utf8.decode(_buffer.sublist(0, headerEnd));
      final Match? match = RegExp(
        r'Content-Length:\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(header);
      if (match == null) {
        _buffer.removeRange(0, headerEnd + 4);
        continue;
      }
      final int length = int.parse(match.group(1)!);
      final int start = headerEnd + 4;
      if (_buffer.length < start + length) return;
      final List<int> body = _buffer.sublist(start, start + length);
      _buffer.removeRange(0, start + length);
      try {
        final Object? decoded = jsonDecode(utf8.decode(body));
        if (decoded is Map<String, dynamic>) _handle(decoded);
      } on FormatException {
        // Ignore malformed frame; next frame can still be parsed.
      }
    }
  }

  int _indexOfHeaderEnd() {
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

  void _handle(Map<String, dynamic> message) {
    final Object? id = message['id'];
    final Object? method = message['method'];
    final Object? params = message['params'];
    if (id != null && method is String) {
      if (method == 'workspace/configuration') {
        final Object? items = params is Map ? params['items'] : null;
        final int count = items is List ? items.length : 0;
        _send(<String, Object?>{
          'jsonrpc': '2.0',
          'id': id,
          'result': List<Object?>.filled(count, null),
        });
      } else {
        _send(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': null});
      }
      return;
    }
    if (id is int) {
      final Completer<Map<String, dynamic>>? pending = _pending.remove(id);
      if (pending != null && !pending.isCompleted) {
        if (message['error'] != null) {
          pending.completeError(LspException('${message['error']}'));
        } else {
          final Object? result = message['result'];
          pending.complete(
            result is Map<String, dynamic> ? result : <String, dynamic>{},
          );
        }
      }
      return;
    }
    if (method == 'textDocument/publishDiagnostics' && params is Map) {
      final Object? uri = params['uri'];
      if (uri is! String) return;
      final List<LspDiagnostic> parsed = _parseDiagnostics(uri, params);
      _diagnostics[uri] = parsed;
      final Completer<List<LspDiagnostic>>? waiter = _waiters[uri];
      if (waiter != null && !waiter.isCompleted) waiter.complete(parsed);
    }
  }

  List<LspDiagnostic> _parseDiagnostics(
    String uri,
    Map<dynamic, dynamic> params,
  ) {
    final String path = Uri.parse(uri).toFilePath();
    final Object? raw = params['diagnostics'];
    if (raw is! List) return const <LspDiagnostic>[];
    return <LspDiagnostic>[
      for (final Object? item in raw)
        if (item is Map)
          LspDiagnostic(
            path: path,
            line: _startValue(item, 'line') + 1,
            column: _startValue(item, 'character') + 1,
            severity: _severity(item['severity'] as int?),
            message: '${item['message'] ?? ''}',
            code: item['code']?.toString(),
          ),
    ];
  }

  int _startValue(Map<dynamic, dynamic> item, String key) {
    final Object? range = item['range'];
    if (range is! Map) return 0;
    final Object? start = range['start'];
    if (start is! Map) return 0;
    final Object? value = start[key];
    return value is int ? value : 0;
  }

  LspSeverity _severity(int? value) => switch (value) {
        1 => LspSeverity.error,
        2 => LspSeverity.warning,
        3 => LspSeverity.information,
        4 => LspSeverity.hint,
        _ => LspSeverity.information,
      };

  String _languageId(String path) {
    final String extension = path.split('.').last.toLowerCase();
    return switch (extension) {
      'dart' => 'dart',
      'ts' || 'tsx' => 'typescript',
      'js' || 'jsx' => 'javascript',
      'py' => 'python',
      'rs' => 'rust',
      'go' => 'go',
      _ => extension,
    };
  }

  void _onExit() {
    _process = null;
    _started = false;
    for (final Completer<Map<String, dynamic>> pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          LspException(_stderr.isEmpty ? 'LSP server exited' : _stderr),
        );
      }
    }
    _pending.clear();
    for (final Completer<List<LspDiagnostic>> waiter in _waiters.values) {
      if (!waiter.isCompleted) waiter.complete(const <LspDiagnostic>[]);
    }
    _waiters.clear();
  }
}

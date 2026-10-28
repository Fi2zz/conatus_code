/// LSP stdio 传输：进程、JSON-RPC 请求/通知与帧循环。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lsp_frame_reader.dart';
import 'lsp_types.dart';

/// 收到 server 通知（如 publishDiagnostics）的回调。
typedef LspNotificationHandler = void Function(Map<String, dynamic> message);

/// 一个 JSON-RPC stdio 传输。
class LspTransport {
  LspTransport({
    required List<String> command,
    required String workdir,
    Map<String, String> env = const <String, String>{},
    this.requestTimeout = const Duration(seconds: 10),
    this.onNotification,
  }) : _command = command,
       _workdir = workdir,
       _env = env;
  final List<String> _command;
  final String _workdir;
  final Map<String, String> _env;
  final Duration requestTimeout;
  final LspNotificationHandler? onNotification;
  final LspFrameReader _frames = LspFrameReader();
  final Map<String, Completer<Object?>> _pending =
      <String, Completer<Object?>>{};
  Process? _process;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  int _nextId = 1;
  String _stderr = '';
  bool _started = false;
  bool _stopping = false;
  bool get running => _process != null && !_stopping;
  int? get serverPid => _process?.pid;
  String get stderr => _stderr;
  Future<void> start() async {
    if (_started) return;
    if (_command.isEmpty) throw const LspException('empty command');
    _frames.reset();
    _stderr = '';
    try {
      final Process process = await Process.start(
        _command.first,
        _command.skip(1).toList(growable: false),
        workingDirectory: _workdir,
        environment: <String, String>{...Platform.environment, ..._env},
      );
      _process = process;
      unawaited(process.stdin.done.catchError((Object _) {}));
      _stdoutSub = process.stdout.listen((List<int> bytes) {
        for (final Map<String, dynamic> message in _frames.add(bytes)) {
          try {
            _handle(message);
          } catch (_) {
            // A single bad message must never escape the stdout listener.
          }
        }
      });
      _stderrSub = process.stderr.listen((List<int> bytes) {
        if (_stderr.length < 8000) {
          _stderr += utf8.decode(bytes, allowMalformed: true);
          if (_stderr.length > 8000) _stderr = _stderr.substring(0, 8000);
        }
      });
      unawaited(process.exitCode.then((int _) => _onExit()));
      _started = true;
    } catch (error) {
      await stop();
      if (error is LspException) rethrow;
      throw LspException('$error');
    }
  }

  Future<Object?> request(String method, Object? params, {Duration? timeout}) {
    final int id = _nextId++;
    final String key = '$id';
    final Completer<Object?> completer = Completer<Object?>();
    _pending[key] = completer;
    _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    return completer.future.timeout(
      timeout ?? requestTimeout,
      onTimeout: () {
        _pending.remove(key);
        throw LspException('$method timed out');
      },
    );
  }

  void notify(String method, Object? params) {
    _send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    final Process? process = _process;
    if (process != null) {
      try {
        await request('shutdown', null, timeout: const Duration(seconds: 1));
        notify('exit', null);
      } catch (_) {
        // Server may already be gone.
      }
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        try {
          await process.exitCode.timeout(const Duration(seconds: 1));
        } on TimeoutException {
          // Give up after the forced-kill grace period.
        }
      }
    }
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process = null;
    _started = false;
    _frames.reset();
    for (final Completer<Object?> pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(const LspException('client stopped'));
      }
    }
    _pending.clear();
    _stopping = false;
  }

  Future<void> close() => stop();

  void _send(Map<String, Object?> message) {
    final Process? process = _process;
    if (process == null) return;
    try {
      final List<int> body = utf8.encode(jsonEncode(message));
      process.stdin.add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
      process.stdin.add(body);
    } on IOException {
      // The server may have exited between the liveness check and the write.
    }
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
    if (id != null) {
      final Completer<Object?>? pending = _pending.remove('$id');
      if (pending != null && !pending.isCompleted) {
        if (message['error'] != null) {
          pending.completeError(LspException('${message['error']}'));
        } else {
          pending.complete(message['result']);
        }
      }
      return;
    }
    onNotification?.call(message);
  }

  void _onExit() {
    _process = null;
    _started = false;
    for (final Completer<Object?> pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          LspException(_stderr.isEmpty ? 'LSP server exited' : _stderr),
        );
      }
    }
    _pending.clear();
  }
}

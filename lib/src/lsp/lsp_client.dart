/// LSP 客户端：文档同步、诊断与导航请求。传输层见 lsp_transport.dart。
library;

import 'dart:async';
import 'dart:io';

import 'lsp_diagnostics_parser.dart';
import 'lsp_transport.dart';
import 'lsp_types.dart';

export 'lsp_types.dart' show LspException, languageIdForPath;

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
  }) : _workdir = workdir,
       _initialization = initialization {
    _transport = LspTransport(
      command: command,
      workdir: workdir,
      env: env,
      requestTimeout: requestTimeout,
      onNotification: _onNotification,
    );
  }

  final String _workdir;
  final Map<String, Object?> _initialization;
  final Duration startTimeout;
  final Duration requestTimeout;
  final Duration diagnosticsWait;
  late final LspTransport _transport;
  final Map<String, List<LspDiagnostic>> _diagnostics =
      <String, List<LspDiagnostic>>{};
  final Map<String, Completer<List<LspDiagnostic>>> _waiters =
      <String, Completer<List<LspDiagnostic>>>{};
  final Map<String, int> _versions = <String, int>{};
  final Set<String> _opened = <String>{};
  bool _started = false;
  bool get running => _transport.running && _started;
  int? get serverPid => _transport.serverPid;

  Future<void> start() async {
    if (_started && _transport.running) return;
    _resetDocumentState();
    await _transport.start();
    try {
      await _transport.request('initialize', <String, Object?>{
        'processId': pid,
        'rootUri': Uri.file(_workdir).toString(),
        'workspaceFolders': <Map<String, Object?>>[
          <String, Object?>{
            'uri': Uri.file(_workdir).toString(),
            'name': _workdir.split(Platform.pathSeparator).last,
          },
        ],
        'capabilities': <String, Object?>{
          'textDocument': <String, Object?>{
            'hover': <String, Object?>{
              'contentFormat': <String>['markdown', 'plaintext'],
            },
            'definition': <String, Object?>{'linkSupport': true},
            'references': <String, Object?>{},
            'documentSymbol': <String, Object?>{
              'hierarchicalDocumentSymbolSupport': true,
            },
          },
        },
        'initializationOptions': _initialization,
      }, timeout: startTimeout);
      _transport.notify('initialized', <String, Object?>{});
      _started = true;
    } catch (error) {
      await _transport.stop();
      if (error is LspException) rethrow;
      throw LspException('$error');
    }
  }

  Future<List<LspDiagnostic>> diagnose(
    String path, {
    String? text,
    bool save = false,
  }) async {
    await _ensureStarted();
    final String uri = Uri.file(path).toString();
    final Completer<List<LspDiagnostic>> waiter =
        Completer<List<LspDiagnostic>>();
    _waiters[uri] = waiter;
    _diagnostics[uri] = const <LspDiagnostic>[];
    try {
      await _syncDocument(path, text: text, save: save);
      return await waiter.future.timeout(diagnosticsWait);
    } on TimeoutException {
      return _diagnostics[uri] ?? const <LspDiagnostic>[];
    } finally {
      _waiters.remove(uri);
    }
  }
  /// 打开/更新文档，供 hover/definition 等请求使用。
  Future<void> ensureDocument(
    String path, {
    String? text,
    bool save = false,
  }) async {
    await _syncDocument(path, text: text, save: save);
  }

  /// 发送一个已初始化后的 LSP 请求；调用方负责 ensureDocument。
  Future<Object?> sendRequest(
    String method,
    Map<String, Object?> params,
  ) async {
    await _ensureStarted();
    return _transport.request(method, params);
  }

  Future<void> stop() async {
    await _transport.stop();
    _started = false;
    _resetDocumentState();
  }

  Future<void> close() => stop();

  Future<void> _ensureStarted() async {
    if (_transport.running && _started) return;
    await start();
  }

  Future<void> _syncDocument(
    String path, {
    String? text,
    bool save = false,
  }) async {
    await _ensureStarted();
    final String uri = Uri.file(path).toString();
    final String content;
    try {
      content = text ?? await File(path).readAsString();
    } on FileSystemException catch (error) {
      throw LspException('cannot read ${error.path ?? path}: ${error.message}');
    }
    final int version = (_versions[uri] ?? 0) + 1;
    _versions[uri] = version;
    if (!_opened.contains(uri)) {
      _opened.add(uri);
      _transport.notify('textDocument/didOpen', <String, Object?>{
        'textDocument': <String, Object?>{
          'uri': uri,
          'languageId': languageIdForPath(path),
          'version': version,
          'text': content,
        },
      });
    } else {
      _transport.notify('textDocument/didChange', <String, Object?>{
        'textDocument': <String, Object?>{'uri': uri, 'version': version},
        'contentChanges': <Map<String, Object?>>[
          <String, Object?>{'text': content},
        ],
      });
      if (save) {
        _transport.notify('textDocument/didSave', <String, Object?>{
          'textDocument': <String, Object?>{'uri': uri},
          'text': content,
        });
      }
    }
  }

  void _onNotification(Map<String, dynamic> message) {
    if (message['method'] != 'textDocument/publishDiagnostics') return;
    final Object? params = message['params'];
    if (params is! Map) return;
    final Object? uri = params['uri'];
    if (uri is! String) return;
    final List<LspDiagnostic> diagnostics = parseLspDiagnostics(uri, params);
    _diagnostics[uri] = diagnostics;
    final Completer<List<LspDiagnostic>>? waiter = _waiters[uri];
    if (waiter != null && !waiter.isCompleted) waiter.complete(diagnostics);
  }

  void _resetDocumentState() {
    _opened.clear();
    _versions.clear();
    _diagnostics.clear();
    for (final Completer<List<LspDiagnostic>> waiter in _waiters.values) {
      if (!waiter.isCompleted) waiter.complete(const <LspDiagnostic>[]);
    }
    _waiters.clear();
  }
}

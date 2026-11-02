/// Node 插件宿主进程：启动、JSON-RPC、超时与关闭。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'plugin_launch.dart';
import 'plugin_protocol.dart';
import 'plugin_types.dart';

/// 宿主日志回调。
typedef PluginHostLog = void Function(String message);

/// 一个长期运行的 Node 插件宿主。
class PluginHost {
  PluginHost({
    required this.node,
    required this.scriptPath,
    required this.candidates,
    required this.workdir,
    this.onLog,
    this.initTimeout = const Duration(seconds: 10),
    this.hookTimeout = const Duration(seconds: 5),
    this.toolTimeout = const Duration(seconds: 60),
  });

  final String node;
  final String scriptPath;
  final List<PluginCandidate> candidates;
  final String workdir;
  final PluginHostLog? onLog;
  final Duration initTimeout;
  final Duration hookTimeout;
  final Duration toolTimeout;

  Process? _process;
  final Map<String, Completer<PluginRpcMessage>> _pending =
      <String, Completer<PluginRpcMessage>>{};
  int _nextId = 1;
  bool _closed = false;

  bool get running => _process != null && !_closed;

  /// 查找 Node：`NAVA_NODE` 优先，其次 PATH 里的 `node`。
  static Future<String?> resolveNode() => resolvePluginNode();

  /// 把内嵌宿主写到缓存目录；按源码哈希版本化。
  static Future<String> ensureHostScript({required String homeDir}) =>
      ensurePluginHostScript(homeDir: homeDir);

  /// 启动宿主并完成初始化。
  Future<PluginInitResult> start() async {
    final Process process = await Process.start(node, <String>[
      scriptPath,
    ], workingDirectory: workdir);
    _process = process;
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) => onLog?.call(line));
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
    unawaited(
      process.exitCode.then((int code) {
        _closed = true;
        onLog?.call('插件宿主退出（$code）');
      }),
    );
    final Map<String, Object?> result = await _request(
      'init',
      <String, Object?>{
        'directory': workdir,
        'worktree': workdir,
        'plugins': <Map<String, Object?>>[
          for (final PluginCandidate candidate in candidates)
            candidate.toInitJson(),
        ],
      },
      timeout: initTimeout,
    );
    return PluginInitResult.fromJson(result);
  }

  /// 调用一个 hook；失败/超时返回空结果（fail-open）。
  Future<Map<String, Object?>> hook(
    String name, {
    Map<String, Object?> input = const <String, Object?>{},
    Map<String, Object?> output = const <String, Object?>{},
  }) async {
    if (!running) return const <String, Object?>{};
    try {
      return await _request('hook', <String, Object?>{
        'name': name,
        'input': input,
        'output': output,
      }, timeout: hookTimeout);
    } on Object catch (error) {
      onLog?.call('hook $name 失败：$error');
      return const <String, Object?>{};
    }
  }

  /// 执行一个插件工具；失败抛异常。
  Future<String> executeTool(
    String name,
    Map<String, Object?> arguments, {
    String? sessionId,
  }) async {
    final Map<String, Object?> result = await _request(
      'tool.execute',
      <String, Object?>{
        'name': name,
        'args': arguments,
        'sessionID': sessionId ?? '',
      },
      timeout: toolTimeout,
    );
    return '${result['output'] ?? ''}';
  }

  /// 发送事件通知。
  void notifyEvent(String type, [Map<String, Object?> data = const {}]) {
    if (!running) return;
    _write(
      PluginRpcCodec.notification('event', <String, Object?>{
        'event': <String, Object?>{'type': type, 'properties': data},
      }),
    );
  }

  /// 关闭宿主：shutdown → 2s 后强杀。
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final Process? process = _process;
    if (process == null) return;
    try {
      _write(PluginRpcCodec.request('shutdown', 'shutdown', const {}));
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on Object {
      process.kill(ProcessSignal.sigkill);
    }
  }

  Future<Map<String, Object?>> _request(
    String method,
    Map<String, Object?> params, {
    required Duration timeout,
  }) async {
    final String id = 'd${_nextId++}';
    final Completer<PluginRpcMessage> completer = Completer<PluginRpcMessage>();
    _pending[id] = completer;
    _write(PluginRpcCodec.request(id, method, params));
    try {
      final PluginRpcMessage message = await completer.future.timeout(timeout);
      final String? error = message.error;
      if (error != null) throw StateError(error);
      return message.result;
    } finally {
      _pending.remove(id);
    }
  }

  void _onLine(String line) {
    final PluginRpcMessage? message = PluginRpcMessage.decode(line);
    if (message == null) return;
    if (message.id != null && _pending.containsKey('${message.id}')) {
      final Completer<PluginRpcMessage> completer = _pending['${message.id}']!;
      if (!completer.isCompleted) completer.complete(message);
      return;
    }
    if (message.isRequest) _handleHostRequest(message);
  }

  void _handleHostRequest(PluginRpcMessage message) {
    // P4.1 的宿主把所有注册信息放在 init 结果里；这里只处理日志请求。
    if (message.method == 'log') {
      onLog?.call('${message.params['message'] ?? ''}');
    }
    _write(PluginRpcCodec.result(message.id!, const <String, Object?>{}));
  }

  void _write(String line) {
    final Process? process = _process;
    if (process == null) throw StateError('插件宿主未启动');
    process.stdin.writeln(line);
  }
}

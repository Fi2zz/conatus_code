/// XERJ 本地节点的懒启动与所有权。
///
/// 只在第一次查询时启动；已存在的 XERJ 节点直接复用（不杀）。数据目录
/// 由调用方指定且必须位于被索引的工作区之外——XERJ 会把 data-dir 当成
/// 普通文件索引进去。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'xerj_binary.dart';
import 'xerj_endpoint.dart';

/// 懒启动的 XERJ 节点。
class XerjNode implements XerjEndpoint {
  XerjNode({
    required this.binary,
    required String dataDir,
    this.url = 'http://127.0.0.1:19200',
    this.startTimeout = const Duration(seconds: 8),
    XerjProcessStarter? starter,
    XerjHealthProbe? probe,
  }) : dataDir = _expandHome(dataDir),
       _starter = starter ?? _startProcess,
       _probe = probe ?? _probeNode;

  /// 可执行文件。
  final XerjBinary binary;

  /// 节点数据目录（必须避开被索引的工作区）。
  final String dataDir;

  /// ES 兼容端点。
  final String url;

  /// 启动后等待健康检查的最长时间。
  final Duration startTimeout;

  final XerjProcessStarter _starter;
  final XerjHealthProbe _probe;

  XerjProcess? _process;
  Future<String?>? _starting;

  /// 当前节点是否由本对象启动（复用既有节点时为 `false`）。
  bool get owned => _process != null;

  @override
  Future<String?> ensureRunning() {
    if (_process != null) return Future<String?>.value(url);
    final Future<String?>? pending = _starting;
    if (pending != null) return pending;
    final Future<String?> start = _ensure();
    _starting = start;
    return start.whenComplete(() => _starting = null);
  }

  /// 停止由本对象启动的节点；复用或未启动时无副作用。幂等。
  Future<void> dispose() async {
    final XerjProcess? process = _process;
    _process = null;
    process?.stop();
  }

  Future<String?> _ensure() async {
    if (await _probe(url)) return url;
    await Directory(dataDir).create(recursive: true);
    final XerjProcess process = await _starter(binary.path, <String>[
      '--insecure',
      '--data-dir',
      dataDir,
      '--port',
      '${Uri.parse(url).port}',
    ]);
    if (!await _awaitReady(process)) {
      process.stop();
      return null;
    }
    _process = process;
    return url;
  }

  /// 轮询健康检查，直到就绪、进程退出或超时。
  Future<bool> _awaitReady(XerjProcess process) async {
    var exited = false;
    unawaited(process.exited.then((_) => exited = true));
    final Stopwatch watch = Stopwatch()..start();
    while (watch.elapsed < startTimeout) {
      if (exited) return false;
      if (await _probe(url)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  static Future<XerjProcess> _startProcess(
    String executable,
    List<String> arguments,
  ) async {
    final Process process = await Process.start(executable, arguments);
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    return _HostedProcess(process);
  }

  /// 只有 `cluster_name == "xerj"` 才算命中，避免误连本机 Elasticsearch。
  static Future<bool> _probeNode(String url) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 300);
    try {
      final HttpClientRequest request = await client.getUrl(Uri.parse(url));
      final HttpClientResponse response = await request.close().timeout(
        const Duration(milliseconds: 500),
      );
      final String body = await response.transform(utf8.decoder).join();
      final Object? json = jsonDecode(body);
      return json is Map<String, Object?> && json['cluster_name'] == 'xerj';
    } on Exception {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static String _expandHome(String path) {
    if (!path.startsWith('~/')) return path;
    final String? home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return home == null ? path : '$home${path.substring(1)}';
  }
}

/// [Process] 的薄包装：退出信号与停止。
class _HostedProcess implements XerjProcess {
  _HostedProcess(this._process);

  final Process _process;

  @override
  Future<void> get exited => _process.exitCode.then((_) {});

  @override
  void stop() {
    _process.kill();
  }
}

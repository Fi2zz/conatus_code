/// LSP 管理器：扩展名路由、按需启动与诊断缓存。
library;

import 'dart:io';

import '../config/config_schema.dart';
import 'lsp_client.dart';
import 'lsp_types.dart';

/// 一个 LSP server 的运行状态。
class LspServerStatus {
  const LspServerStatus({
    required this.name,
    required this.state,
    this.error,
    this.diagnosticCount = 0,
  });

  final String name;

  /// `disabled` / `idle` / `running` / `error`。
  final String state;
  final String? error;
  final int diagnosticCount;
}

/// 按配置管理多个 LSP server。
class LspManager implements LspDiagnosticsSource {
  LspManager({
    required this.config,
    required this.workdir,
    LspClient Function(LspServerConfig server)? clientFactory,
  }) : _clientFactory =
            clientFactory ?? ((LspServerConfig server) => _makeClient(server, workdir)) {
    buildRoutes();
  }

  final LspConfig config;
  final String workdir;
  final LspClient Function(LspServerConfig server) _clientFactory;
  final Map<String, LspClient> _clients = <String, LspClient>{};
  final Map<String, String> _extensions = <String, String>{};
  final Map<String, String> _errors = <String, String>{};
  final Map<String, int> _counts = <String, int>{};

  /// 已启用的服务器。
  Iterable<LspServerConfig> get activeServers =>
      config.servers.where((LspServerConfig server) => !server.disabled);

  /// 按扩展名找服务器；找不到返回 `null`。
  LspServerConfig? serverFor(String path) {
    if (!config.enabled) return null;
    final int dot = path.lastIndexOf('.');
    if (dot < 0) return null;
    final String extension = path.substring(dot).toLowerCase();
    final String? name = _extensions[extension];
    if (name == null) return null;
    for (final LspServerConfig server in config.servers) {
      if (server.name == name && !server.disabled) return server;
    }
    return null;
  }

  /// 对 [path] 取诊断；未配置/失败返回空列表。
  @override
  Future<List<LspDiagnostic>> diagnose(String path) =>
      _diagnose(path, save: false);

  /// 文件编辑后刷新诊断，并发送 didSave。
  @override
  Future<List<LspDiagnostic>> fileChanged(String path) =>
      _diagnose(path, save: true);

  Future<List<LspDiagnostic>> _diagnose(
    String path, {
    required bool save,
  }) async {
    final String absolute = File(path).isAbsolute
        ? path
        : '$workdir${Platform.pathSeparator}$path';
    final LspServerConfig? server = serverFor(absolute);
    if (server == null) return const <LspDiagnostic>[];
    try {
      final LspClient client = await _clientFor(server);
      final List<LspDiagnostic> diagnostics = await client.diagnose(
        absolute,
        save: save,
      );
      _counts[server.name] = diagnostics.length;
      _errors.remove(server.name);
      return diagnostics;
    } catch (error) {
      _errors[server.name] = '$error';
      _counts[server.name] = 0;
      return const <LspDiagnostic>[];
    }
  }

  List<LspServerStatus> statuses() {
    return <LspServerStatus>[
      for (final LspServerConfig server in config.servers)
        LspServerStatus(
          name: server.name,
          state: server.disabled
              ? 'disabled'
              : _clients.containsKey(server.name)
                  ? 'running'
                  : _errors.containsKey(server.name)
                      ? 'error'
                      : 'idle',
          error: _errors[server.name],
          diagnosticCount: _counts[server.name] ?? 0,
        ),
    ];
  }

  /// 重启指定服务器；不传则重启全部。
  Future<void> restart([String? name]) async {
    final Iterable<String> names =
        name == null ? _clients.keys.toList(growable: false) : <String>[name];
    for (final String item in names) {
      final LspClient? client = _clients.remove(item);
      await client?.stop();
      _errors.remove(item);
      _counts[item] = 0;
    }
  }

  Future<void> close() async {
    for (final LspClient client in _clients.values) {
      await client.stop();
    }
    _clients.clear();
  }

  Future<LspClient> _clientFor(LspServerConfig server) async {
    final LspClient? existing = _clients[server.name];
    if (existing != null) return existing;
    final LspClient client = _clientFactory(server);
    _clients[server.name] = client;
    try {
      await client.start();
      return client;
    } catch (error) {
      _clients.remove(server.name);
      _errors[server.name] = '$error';
      rethrow;
    }
  }

  /// 构建扩展名索引；同名扩展名以最后配置的服务器为准。
  void buildRoutes() {
    _extensions.clear();
    for (final LspServerConfig server in config.servers) {
      if (server.disabled) continue;
      for (final String extension in server.extensions) {
        _extensions[extension] = server.name;
      }
    }
  }

  /// 工作区根（供调用方展示/测试）。
  bool get enabled => config.enabled;
  Directory get root => Directory(workdir);
}

LspClient _makeClient(LspServerConfig server, String workdir) {
  return LspClient(
    command: server.command,
    workdir: workdir,
    env: server.env,
    initialization: server.initialization,
  );
}

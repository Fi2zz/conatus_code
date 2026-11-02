/// 插件服务：启动宿主、注册工具/技能、挂工具中间件与事件出口。
library;

import 'dart:async';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'plugin_config.dart';
import 'plugin_env_shell.dart';
import 'plugin_host.dart';
import 'plugin_tool.dart';
import 'plugin_types.dart';

/// 已装配的插件服务；服务键 `'plugins'`。
class PluginService implements PluginServiceLike {
  PluginService._({
    required this.host,
    required this.result,
    required this.warnings,
    required this.warn,
  }) : available = true;

  PluginService._disabled({required this.warnings, required this.warn})
    : host = null,
      result = const PluginInitResult(),
      available = false;

  final PluginHost? host;
  final PluginInitResult result;

  @override
  final bool available;

  /// 启动/加载阶段的告警。
  final List<String> warnings;

  final void Function(String message) warn;

  @override
  List<String> get skillRoots => result.skillRoots;

  @override
  String get contextText => result.context;

  @override
  Map<String, String> get shellEnv => result.shellEnv;

  /// 启动插件：无候选、无 Node、初始化失败都返回 no-op 服务。
  static Future<PluginService> start({
    required List<PluginCandidate> candidates,
    required String workdir,
    required String homeDir,
    required ToolRegistry tools,
    void Function(String message)? warn,
    PluginHost? hostOverride,
  }) async {
    final void Function(String) log = warn ?? ((String message) {});
    if (candidates.isEmpty) {
      return PluginService._disabled(warnings: const <String>[], warn: log);
    }
    final String? node = hostOverride == null
        ? await PluginHost.resolveNode()
        : 'node';
    if (node == null) {
      log('插件不可用：未找到 node（可用 NAVA_NODE 指定）。');
      return PluginService._disabled(
        warnings: <String>['未找到 node，插件未加载。'],
        warn: log,
      );
    }
    final String script = hostOverride == null
        ? await PluginHost.ensureHostScript(homeDir: homeDir)
        : '';
    final PluginHost host =
        hostOverride ??
        PluginHost(
          node: node,
          scriptPath: script,
          candidates: candidates,
          workdir: workdir,
          onLog: log,
        );
    try {
      final PluginInitResult result = await host.start();
      final PluginService service = PluginService._(
        host: host,
        result: result,
        warnings: result.warnings,
        warn: log,
      );
      service._register(tools);
      return service;
    } on Object catch (error) {
      log('插件宿主启动失败：$error');
      await host.close();
      return PluginService._disabled(
        warnings: <String>['插件宿主启动失败：$error'],
        warn: log,
      );
    }
  }

  void _register(ToolRegistry tools) {
    for (final PluginToolSpec tool in result.tools) {
      try {
        tools.register(
          PluginTool(
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters,
            execute: (Map<String, Object?> args, String callId) =>
                host!.executeTool(tool.name, args),
          ),
        );
      } on StateError catch (error) {
        warn('插件工具注册失败：$error');
      }
    }
    tools.use(_middleware);
    tools.onResult(_onResult);
  }

  Future<ToolResult> _middleware(
    ToolCall call,
    Future<ToolResult> Function() next,
  ) async {
    final Map<String, Object?> before = await host!.hook(
      'tool.execute.before',
      input: <String, Object?>{'tool': call.name, 'callID': call.callId},
      output: <String, Object?>{'args': call.arguments},
    );
    if (before['blocked'] == true) {
      return ToolResult.failure(
        '插件拒绝工具：${before['reason'] ?? 'no reason'}',
        error: const ToolError('PLUGIN_REJECTED', 'plugin rejected'),
      );
    }
    final ToolResult result = await next();
    final Map<String, Object?> after = await host!.hook(
      'tool.execute.after',
      input: <String, Object?>{'tool': call.name, 'callID': call.callId},
      output: <String, Object?>{
        'title': call.name,
        'output': result.content,
        'metadata': <String, Object?>{},
      },
    );
    final Object? output = after['output'];
    final String content = output is Map && output['output'] is String
        ? output['output'] as String
        : result.content;
    if (content == result.content) return result;
    return result.isError
        ? ToolResult.failure(content, error: result.error)
        : ToolResult.success(content, value: result.value);
  }

  void _onResult(ToolCall call, ToolResult result) {
    if (result.isError) return;
    if (call.name != 'write' &&
        call.name != 'edit' &&
        call.name != 'apply_patch') {
      return;
    }
    final Object? path = call.arguments['filePath'] ?? call.arguments['path'];
    unawaited(
      notify('file.edited', <String, Object?>{'file': '${path ?? ''}'}),
    );
  }

  /// 发送一个事件给插件的 `event` hook。
  @override
  Future<void> notify(
    String event, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) async {
    host?.notifyEvent(event, data);
  }

  /// 把插件 `shell.env` 注入 shell 执行器。
  ShellExecutor wrapShell(ShellExecutor inner) {
    if (shellEnv.isEmpty) return inner;
    return PluginEnvShell(inner: inner, env: shellEnv);
  }

  /// 关闭宿主；幂等。
  Future<void> close() async {
    await host?.close();
  }
}

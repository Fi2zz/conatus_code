/// Hooks：用户配置的命令在工具执行前/后与轮次收口时运行。
///
/// 事件：`pre_tool_use`（任一失败即拒绝工具）/ `post_tool_use`（失败只追加
/// 提示）/ `stop`（轮次收口，失败只提示）。hook 命令经 `/bin/sh -c` 直连起
/// 进程（**不经过 `'shell'` 缝**，避免沙箱递归裁决用户本机命令）。环境变量：
/// `NAVA_HOOK_EVENT` / `NAVA_HOOK_TOOL` / `NAVA_HOOK_ARGS_JSON`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import '../config/config_schema.dart';

/// 一次 hook 命令的运行结果。
class HookResult {
  const HookResult({required this.exitCode, required this.output});

  /// 退出码。
  final int exitCode;

  /// 合并的 stdout+stderr（去尾空白）。
  final String output;

  /// 是否成功。
  bool get ok => exitCode == 0;
}

/// 按序执行 [commands]，注入 [env]；命令经 `/bin/sh -c` 运行。
///
/// 命令缺失/执行异常按 `exitCode 127` 计（不抛出）。
Future<List<HookResult>> runHooks(
  List<String> commands,
  String event, {
  Map<String, String> env = const <String, String>{},
}) async {
  final List<HookResult> results = <HookResult>[];
  for (final String command in commands) {
    try {
      final ProcessResult result = await Process.run(
        '/bin/sh',
        <String>['-c', command],
        environment: <String, String>{'NAVA_HOOK_EVENT': event, ...env},
      );
      results.add(HookResult(
        exitCode: result.exitCode,
        output: '${result.stdout}${result.stderr}'.trim(),
      ));
    } on ProcessException catch (error) {
      results.add(HookResult(exitCode: 127, output: '命令不可用：$error'));
    }
  }
  return results;
}

/// 已装配的 hooks；服务键 `'hooks'`。
class Hooks {
  Hooks({required HooksConfig config}) : _config = config;

  final HooksConfig _config;

  /// 是否有任一事件配了命令。
  bool get any =>
      _config.preToolUse.isNotEmpty ||
      _config.postToolUse.isNotEmpty ||
      _config.stop.isNotEmpty;

  /// PreToolUse：任一 hook 失败返回拒绝理由（`null` = 放行）。
  Future<String?> preToolUse(ToolCall call) =>
      _firstFailure(_config.preToolUse, 'pre_tool_use', call);

  /// PostToolUse：返回失败提示（`null` = 通过）。
  Future<String?> postToolUse(ToolCall call) =>
      _firstFailure(_config.postToolUse, 'post_tool_use', call);

  /// Stop：轮次收口，返回失败提示（`null` = 通过）。
  Future<String?> onStop() async {
    if (_config.stop.isEmpty) return null;
    return _firstFailureOf(await runHooks(_config.stop, 'stop'));
  }

  Future<String?> _firstFailure(
    List<String> commands,
    String event,
    ToolCall call,
  ) async {
    if (commands.isEmpty) return null;
    final List<HookResult> results = await runHooks(
      commands,
      event,
      env: <String, String>{
        'NAVA_HOOK_TOOL': call.name,
        'NAVA_HOOK_ARGS_JSON': jsonEncode(call.arguments),
      },
    );
    return _firstFailureOf(results);
  }

  String? _firstFailureOf(List<HookResult> results) {
    for (final HookResult result in results) {
      if (!result.ok) {
        return result.output.isEmpty
            ? 'hook 退出码 ${result.exitCode}'
            : result.output;
      }
    }
    return null;
  }

  /// 挂到 [ToolRegistry] 中间件：Pre 拒绝工具、Post 追加提示到结果。
  Disposer mount(ToolRegistry tools) {
    if (!any) return () {};
    return tools.use((ToolCall call, Future<ToolResult> Function() next) async {
      final String? denial = await preToolUse(call);
      if (denial != null) {
        return ToolResult.failure(
          'PreToolUse hook 拒绝：$denial',
          error: const ToolError('HOOK_REJECTED', 'pre-tool-use'),
        );
      }
      final ToolResult result = await next();
      final String? note = await postToolUse(call);
      if (note == null) return result;
      return ToolResult.success(
        '${result.content}\n\n[PostToolUse] $note',
        value: result.value,
      );
    });
  }
}

/// 装配：注册 `'hooks'` 服务并挂中间件，返回 Hooks。
Hooks provideHooks(
  Context ctx, {
  required HooksConfig config,
  ToolRegistry? tools,
}) {
  final Hooks hooks = Hooks(config: config);
  ctx.provide('hooks', hooks);
  ctx.effect(() => hooks.mount(tools ?? ctx.tools));
  return hooks;
}

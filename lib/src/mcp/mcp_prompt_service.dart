/// MCP prompt 命令的按需加载。
library;

import 'package:conatus_mcp/conatus_mcp.dart';

import '../commands/command_registry.dart';
import 'mcp_prompt_commands.dart';

/// 装配期只持有连接，不请求 prompts 目录。
///
/// 一次 `prompts/list` 是若干个网络往返，而这些 `/<server>:<prompt>` 命令只有
/// 用户打开命令菜单（或直接敲）时才用得上——放在首帧之前纯属浪费。
class McpPromptCommands {
  McpPromptCommands({
    required this.registry,
    required this.commands,
    this.warn,
  });

  /// 已接入的 MCP server。
  final McpRegistry registry;

  /// prompt 命令登记进这个注册表（动态条目，磁盘命令优先）。
  final CommandRegistry commands;

  /// 列表失败时的告警出口（缺省静默，由调用方决定）。
  final void Function(String message)? warn;

  bool _loaded = false;
  Future<void>? _pending;

  /// 是否已完成一次加载。
  ///
  /// 失败也算完成：外部进程坏掉时不该在每次敲 `/` 时重试一遍。
  bool get loaded => _loaded;

  /// 幂等加载；并发调用共享同一次请求。
  Future<void> ensureLoaded() => _pending ??= _load();

  Future<void> _load() async {
    try {
      registerMcpPromptCommands(
        commands,
        await loadMcpPromptCommands(registry, onWarning: warn),
      );
    } catch (error) {
      warn?.call('MCP prompt 命令加载失败：$error');
    } finally {
      _loaded = true;
    }
  }
}

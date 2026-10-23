/// 自定义命令分发：模板展开 + Agent 解析 + 菜单描述。
library;

import '../agents/agent_definition.dart';
import '../agents/agent_registry.dart';
import '../providers/provider_registry.dart';
import 'command_definition.dart';
import 'command_expander.dart';
import 'command_registry.dart';

/// 把 [CommandRegistry] 里的命令定义接到运行时能力上。
///
/// 只做「查定义 → 展开模板」与少量投影，不负责切换 Agent / 模型：那属于会话
/// 控制器（需要重建 Agent Loop）。[runShell] 缺省不可用，缺省时含 shell 块的
/// 命令展开失败并抛 [StateError]。
class CommandDispatcher {
  /// 创建分发器。
  CommandDispatcher({
    required this.registry,
    required this.agents,
    required this.providers,
    Future<String> Function(String command)? runShell,
  }) : _runShell = runShell;

  /// 命令注册表（发现已完成，这里只读）。
  final CommandRegistry registry;

  /// Agent 注册表；用于解析命令里的 `agent` 字段。
  final AgentRegistry agents;

  /// 模型提供商注册表；`null` 表示未配置提供商。
  final ProviderRegistry? providers;

  final Future<String> Function(String command)? _runShell;

  /// 全部自定义命令（按名称排序）。
  List<CommandDefinition> get all => registry.all;

  /// 精确查找一条命令。
  CommandDefinition? byName(String name) => registry.byName(name);

  /// 展开命令模板；shell 块经 [runShell]，失败向上抛出。
  Future<String> expand(CommandDefinition def, String args) =>
      expandCommand(def, args, runShell: _runShell ?? _shellUnavailable);

  /// 解析命令声明的 Agent；未声明或未注册返回 `null`。
  AgentDefinition? agentFor(CommandDefinition def) {
    final String? id = def.agent;
    return id == null ? null : agents.byId(id);
  }

  /// 菜单描述：原始描述 + agent / model / subagent 提示。
  String menuDescription(CommandDefinition def) {
    final List<String> hints = <String>[];
    if (def.agent != null) {
      hints.add('agent: ${def.agent}');
    }
    if (def.model != null) {
      hints.add('model: ${def.model}');
    }
    if (def.subagent) {
      hints.add('前台子 Agent');
    }
    final String base = def.description.trim().isEmpty
        ? '自定义命令'
        : def.description.trim();
    return hints.isEmpty ? base : '$base · ${hints.join(' · ')}';
  }

  Future<String> _shellUnavailable(String command) async =>
      throw StateError('shell 不可用，无法展开 !`$command`');
}

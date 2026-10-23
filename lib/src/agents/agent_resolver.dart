/// 把 nava 的 AgentRegistry 定义解析成 `spawn_agent` 的 [SubAgentProfile]。
library;

import 'package:conatus_agent/conatus_agent.dart'
    show SubAgentPermission, SubAgentProfile, SubAgentProfileResolver;
import 'package:conatus_llm/conatus_llm.dart';

import '../providers/provider_registry.dart';
import 'agent_definition.dart';
import 'agent_registry.dart';

/// Agent 定义 → 子 Agent profile。
///
/// 内置 `explore` / `plan` 映射为只读档；`general` 与自定义 Agent 继承宿主
/// 权限（自定义 Agent 自带规则仍会追加）。`model` 为 `provider/model` 时经
/// [ProviderRegistry] 构造模型，构造失败返回 `null`，由 spawn 回退宿主模型。
class AgentProfileResolver implements SubAgentProfileResolver {
  /// 创建解析器；[providers] 缺省时任何 `model` 都回退宿主模型。
  AgentProfileResolver({required this.registry, this.providers});

  /// Agent 注册表。
  final AgentRegistry registry;

  /// 模型提供商注册表。
  final ProviderRegistry? providers;

  @override
  Future<SubAgentProfile?> resolve(String agentId) async {
    final AgentDefinition? agent = registry.byId(agentId);
    if (agent == null) return null;
    return SubAgentProfile(
      id: agent.id,
      system: agent.system,
      steps: agent.steps,
      tools: agent.tools,
      disabledTools: agent.disabledTools,
      permissions: agent.permissions,
      llm: _llm(agent.model),
      permissionMode: _mode(agent),
    );
  }

  /// 内置只读 Agent 走 readonly 档；其余继承宿主。
  SubAgentPermission _mode(AgentDefinition agent) => switch (agent.id) {
    'explore' || 'plan' => SubAgentPermission.readonly,
    _ => SubAgentPermission.inherit,
  };

  /// `provider/model` → 提供商注册表；拆分失败或构造失败返回 `null`。
  LlmProvider? _llm(String? spec) {
    final ProviderRegistry? registry = providers;
    final String? value = spec?.trim();
    if (registry == null || value == null || value.isEmpty) return null;
    final int slash = value.indexOf('/');
    final String provider = slash < 0
        ? value
        : value.substring(0, slash).trim();
    final String? model = slash < 0 ? null : value.substring(slash + 1).trim();
    if (provider.isEmpty || (model != null && model.isEmpty)) return null;
    try {
      return registry.buildLlm(provider, model: model);
    } on Object {
      return null;
    }
  }
}

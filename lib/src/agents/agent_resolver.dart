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
/// 权限（自定义 Agent 自带规则仍会追加）。用 [AgentRegistry.byId] 解析，因此
/// **primary 与 hidden Agent 也可按 ID spawn**（`plan` 依赖这一行为）；是否存在
/// 于选择器由调用方按 `subagents` 决定。
///
/// [AgentDefinition.model] 为 `provider/model` 时经 [ProviderRegistry] 构造模型，
/// 同一 `provider/model` 只构造一次（长生命周期 provider 由 [close] 释放）。
/// 构造失败不静默：记录到 [warnings] 并返回 `null`，由 spawn 回退宿主模型。
class AgentProfileResolver implements SubAgentProfileResolver {
  /// 创建解析器；[providers] 缺省时任何 `model` 都回退宿主模型。
  AgentProfileResolver({required this.registry, this.providers});

  /// Agent 注册表。
  final AgentRegistry registry;

  /// 模型提供商注册表。
  final ProviderRegistry? providers;

  final Map<String, LlmProvider?> _llmCache = <String, LlmProvider?>{};
  final List<String> _warnings = <String>[];

  /// 解析期间的非致命问题（未知 / 非法的 `provider/model` 等）。
  List<String> get warnings => List<String>.unmodifiable(_warnings);

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
      llm: _llm(agent.id, agent.model),
      permissionMode: _mode(agent),
    );
  }

  /// 释放缓存中由本解析器构造的 provider。
  void close() {
    for (final LlmProvider? provider in _llmCache.values) {
      provider?.close();
    }
    _llmCache.clear();
  }

  /// 内置只读 Agent 走 readonly 档；其余继承宿主。
  SubAgentPermission _mode(AgentDefinition agent) => switch (agent.id) {
    'explore' || 'plan' => SubAgentPermission.readonly,
    _ => SubAgentPermission.inherit,
  };

  /// `provider/model` → 提供商注册表；失败记录 warning 并返回 `null`。
  LlmProvider? _llm(String agentId, String? spec) {
    final String? value = spec?.trim();
    if (value == null || value.isEmpty) return null;
    if (_llmCache.containsKey(value)) return _llmCache[value];
    final LlmProvider? provider = _build(agentId, value);
    _llmCache[value] = provider;
    return provider;
  }

  LlmProvider? _build(String agentId, String value) {
    final ProviderRegistry? registry = providers;
    if (registry == null) {
      _warn(agentId, value, '未装配 ProviderRegistry');
      return null;
    }
    final int slash = value.indexOf('/');
    final String provider = slash < 0
        ? value
        : value.substring(0, slash).trim();
    final String? model = slash < 0 ? null : value.substring(slash + 1).trim();
    if (provider.isEmpty || (model != null && model.isEmpty)) {
      _warn(agentId, value, '模型标识不是 provider/model');
      return null;
    }
    try {
      final LlmProvider? built = registry.buildLlm(provider, model: model);
      if (built == null) _warn(agentId, value, '提供商或模型不可用');
      return built;
    } on Object {
      _warn(agentId, value, '构造模型失败');
      return null;
    }
  }

  void _warn(String agentId, String spec, String reason) {
    _warnings.add('Agent "$agentId" 的 model "$spec" 无法解析：$reason，回退宿主模型');
  }
}

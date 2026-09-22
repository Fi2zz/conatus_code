part of 'tui_controller.dart';

/// `/provider` 与 `/model` 的提供商 / 模型切换实现。
///
/// 拆成 part 是为了让 `tui_controller.dart` 只保留命令分派：这里集中注册表
/// 读取、浮层数据与 LLM 服务替换。
extension _ProviderCommands on ConatusTuiController {
  /// `/provider`：只读展示 config 里配置的提供商（增删改走 config.toml）。
  Future<void> _handleProvider(String arg) async {
    final ProviderRegistry? registry = _app.providers;
    if (registry == null) {
      transcript.add(TuiRole.system, '提供商管理未装配：config.toml 未配置 [providers]。');
      return;
    }
    providerPrompt.show(providerItems(registry));
  }

  /// `/plan`：打开 Plan Mode 面板（状态 + 当前计划；面板 Enter 切换）。
  void _openPlanPanel() {
    final PlanMode? planMode = _planMode;
    final Session? session = _session;
    if (planMode == null || session == null) {
      transcript.add(TuiRole.system, 'Plan Mode 不可用：会话尚未绑定。');
      return;
    }
    planPrompt.show(
      active: planMode.state == PlanModeState.active,
      plan: readPlan(session),
    );
  }

  /// 面板 Enter：切换 Plan Mode 并刷新面板。
  Future<void> _confirmPlanPanel() async {
    final PlanMode? planMode = _planMode;
    final Session? session = _session;
    if (planMode == null || session == null) {
      return;
    }
    _togglePlanMode();
    planPrompt.refresh(
      active: planMode.state == PlanModeState.active,
      plan: readPlan(session),
    );
    _refresh();
  }

  /// `/model [名字]`：查看 / 切换当前提供商的模型。
  ///
  /// 装配了注册表时直接切换模型名；否则委托宿主的 [onModelCommand] 钩子。
  Future<void> _handleModel(String arg) async {
    final ProviderRegistry? registry = _app.providers;
    if (registry?.current != null) {
      await _handleModelOf(registry!, arg);
      return;
    }
    final Future<String?> Function(String)? hook = onModelCommand;
    if (hook == null) {
      transcript.add(TuiRole.system, '模型切换未装配：宿主未注入 /model 钩子。');
      return;
    }
    final String? message = await hook(arg);
    if (message != null) {
      transcript.add(TuiRole.system, message);
    }
  }

  Future<void> _handleModelOf(ProviderRegistry registry, String arg) async {
    if (arg.isEmpty) {
      transcript.add(TuiRole.system, '当前提供商：${registry.currentName}\n'
          '用法：/model <模型名>');
      return;
    }
    transcript.add(TuiRole.system,
        await _applyLlm(registry, registry.currentName ?? '', model: arg));
  }

  /// 浮层列表项（只读：仅展示 config 配置的提供商）。
  List<TuiProviderItem> providerItems(ProviderRegistry registry) =>
      <TuiProviderItem>[
        for (final ProviderProfile profile in registry.profiles)
          TuiProviderItem(
            name: profile.name,
            baseUrl: profile.baseUrl,
            current: profile.name == registry.currentName,
          ),
      ];

  /// 按 provider（可指定模型）替换 LLM 服务并重绑；返回提示文本。
  Future<String> _applyLlm(
    ProviderRegistry registry,
    String provider, {
    String? model,
  }) async {
    final void Function(FallbackLlm)? swap = switchLlm;
    final LlmProvider? llm = registry.buildLlm(provider, model: model);
    if (swap == null || llm == null) {
      return '无法切换到 $provider：'
          '${swap == null ? '未注入 LLM 替换钩子' : '没有可用模型'}';
    }
    final String label =
        model ?? registry.byName(provider)?.defaultModel ?? provider;
    swap(FallbackLlm(<LlmProvider>[llm]));
    modelLabel = label;
    final bool rebound = await rebind();
    return '已切换到 $provider · $label${rebound ? '' : '（有在途轮次，稍后生效）'}';
  }
}

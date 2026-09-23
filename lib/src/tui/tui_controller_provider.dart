part of 'tui_controller.dart';

/// `/provider` 与 `/model` 的提供商 / 模型切换实现。
///
/// 拆成 part 是为了让 `tui_controller.dart` 只保留命令分派：这里集中注册表
/// 读取、浮层数据与 LLM 服务替换。
extension _ProviderCommands on ConatusTuiController {
  /// `/provider [add]`：展示 config 配置的提供商；`add` 打开新增表单。
  ///
  /// 新增会写回 config.toml；第一个 provider 同时设为 `default_model`。
  Future<void> _handleProvider(String arg) async {
    final ProviderRegistry? registry = _app.providers;
    if (registry == null) {
      transcript.add(TuiRole.system, '提供商管理未装配：config.toml 未配置 [providers]。');
      return;
    }
    if (arg.trim() == 'add') {
      await _addProvider(registry);
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

  /// 浮层列表项（末尾为新增入口）。
  List<TuiProviderItem> providerItems(ProviderRegistry registry) =>
      <TuiProviderItem>[
        for (final ProviderProfile profile in registry.profiles)
          TuiProviderItem(
            name: profile.name,
            baseUrl: profile.baseUrl,
            current: profile.name == registry.currentName,
          ),
        const TuiProviderItem(name: '', baseUrl: '', current: false, isAdd: true),
      ];

  /// 面板 Enter：选中新增入口时打开表单。
  Future<void> _confirmProviderItem() async {
    final ProviderRegistry? registry = _app.providers;
    final TuiProviderItem? item = providerPrompt.selected;
    if (registry == null || item == null || !item.isAdd) {
      return;
    }
    providerPrompt.close();
    await _addProvider(registry);
  }

  /// 新增 provider：填 base_url / model（name 可选、type 固定 openai）。
  ///
  /// 写回 config.toml；第一个 provider 同时设为 `default_model`（后续不改它）。
  Future<void> _addProvider(ProviderRegistry registry) async {
    final Map<String, String>? values = await formPrompt.ask(TuiFormRequest(
      title: 'Add provider',
      hint: '写回 config.toml；第一个 provider 同时设为 default_model。',
      fields: <TuiFormField>[
        TuiFormField(label: 'base_url', placeholder: 'https://api.deepseek.com'),
        TuiFormField(label: 'model', placeholder: 'deepseek-chat'),
        TuiFormField(label: 'name (可选)', placeholder: '留空自动从 base_url 推导'),
      ],
    ));
    if (values == null) {
      transcript.add(TuiRole.system, '已取消新增。');
      return;
    }
    final String baseUrl = (values['base_url'] ?? '').trim();
    final String model = (values['model'] ?? '').trim();
    if (baseUrl.isEmpty || model.isEmpty) {
      transcript.add(TuiRole.system, 'base_url / model 不能为空。');
      return;
    }
    final String typedName = (values['name (可选)'] ?? '').trim();
    final String name = typedName.isEmpty
        ? registry.uniqueName(deriveProviderName(baseUrl))
        : registry.uniqueName(typedName);
    final String? path = _app.get<String>('configPath');
    if (path != null) {
      appendProviderToFile(
        path,
        name: name,
        baseUrl: baseUrl,
        apiKey: '',
        type: 'openai',
        defaultModel: registry.profiles.isEmpty ? '$name/$model' : null,
      );
    }
    registry.add(ProviderProfile(
      name: name,
      baseUrl: baseUrl,
      models: <String>[model],
    ));
    providerPrompt.refresh(providerItems(registry));
    transcript.add(TuiRole.system, '已添加提供商 $name（写入 config.toml）');
    transcript.add(
        TuiRole.system, await _applyLlm(registry, name, model: model));
  }

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

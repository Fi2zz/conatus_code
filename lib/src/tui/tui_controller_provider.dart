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

  /// `/model [搜索词]`：打开模型选择浮层；选中后切换当前提供商的模型。  ///
  /// 候选优先取配置内模型（`[models.*]`），配置无清单时从 models.dev 兜底；
  /// 参数作为初始搜索词预填。未装配注册表时委托宿主的 [onModelCommand] 钩子，
  /// 两者都不可用时提示先配置提供商（没有缺省回退链，见 README）。
  Future<void> _handleModel(String arg) async {
    final ProviderRegistry? registry = _app.providers;
    final ProviderProfile? current = registry?.current;
    if (current != null) {
      final List<TuiModelItem> items = await _modelCandidates(registry!);
      final TuiModelItem? item = await modelPrompt.choose(items, initialQuery: arg);
      if (item == null) {
        transcript.add(TuiRole.system, '已取消模型切换。');
        return;
      }
      // 回填上下文窗口不阻塞切换：models.dev 冷缓存时联网可达 30s。
      unawaited(_resolveModelContext(item));
      transcript.add(TuiRole.system,
          await _applyLlm(registry, item.provider, model: item.model));
      return;
    }
    final Future<String?> Function(String)? hook = onModelCommand;
    if (hook != null) {
      final String? message = await hook(arg);
      if (message != null) {
        transcript.add(TuiRole.system, message);
      }
      return;
    }
    transcript.add(TuiRole.system, '尚未配置模型提供商：用 /provider add 添加，'
        '或编辑 config.toml 的 [providers]。');
  }

  /// `/model` 浮层候选：所有已注册 provider 的配置模型 + models.dev 兜底。
  ///
  /// 跨 provider 聚合，浮层的 provider 过滤标签（Tab）随之可用——注册了
  /// 某 provider 的 Key 后即可在此面板选它的模型，无需先切到该 provider。
  Future<List<TuiModelItem>> _modelCandidates(ProviderRegistry registry) async {
    final List<TuiModelItem> items = <TuiModelItem>[];
    final Set<String> seen = <String>{};
    for (final ProviderProfile profile in registry.profiles) {
      for (final String model in profile.models) {
        if (!seen.add('${profile.name}/$model')) continue;
        items.add(TuiModelItem(
          provider: profile.name,
          model: model,
          current: profile.name == registry.currentName && model == modelLabel,
        ));
      }
    }
    // 当前模型不在清单里（如 provider 无清单或手工指定）时补一条 current 项。
    final String? currentName = registry.currentName;
    if (modelLabel.isNotEmpty && currentName != null) {
      if (seen.add('$currentName/$modelLabel')) {
        items.add(TuiModelItem(
          provider: currentName,
          model: modelLabel,
          current: true,
        ));
      }
    }
    await _enrichFromModelsDev(registry, items, seen);
    return items;
  }

  /// 从 models.dev 补充候选：一次拉取共享 catalog，对缺清单的 provider 兜底。
  Future<void> _enrichFromModelsDev(
    ProviderRegistry registry,
    List<TuiModelItem> items,
    Set<String> seen,
  ) async {
    final List<ProviderProfile> need = <ProviderProfile>[
      for (final ProviderProfile p in registry.profiles) if (p.models.isEmpty) p,
    ];
    if (need.isEmpty) {
      return;
    }
    transcript.add(TuiRole.system, '正在从 models.dev 获取模型…');
    final Future<Map<String, List<ModelsDevModel>>> Function() loader =
        modelsDevLoader ?? _defaultModelsDevLoader;
    final Map<String, List<ModelsDevModel>> catalog;
    try {
      catalog = await loader();
    } on ModelsDevException catch (error) {
      transcript.add(
          TuiRole.system, '模型清单拉取失败：${error.message}（仅展示配置内模型）。');
      return;
    }
    for (final ProviderProfile profile in need) {
      _appendModelsDev(profile, catalog, items, seen);
    }
  }

  /// 把 models.dev 里某 provider 的编码可用模型追加进候选（按 id 去重）。
  void _appendModelsDev(
    ProviderProfile profile,
    Map<String, List<ModelsDevModel>> catalog,
    List<TuiModelItem> items,
    Set<String> seen,
  ) {
    for (final ModelsDevModel model
        in catalog[profile.name] ?? const <ModelsDevModel>[]) {
      if (!keepForCoding(model.toolCall, model.reasoning)) continue;
      if (!seen.add('${profile.name}/${model.id}')) continue;
      items.add(TuiModelItem(
        provider: profile.name,
        model: model.id,
        contextLength: model.contextLength,
        vision: model.supportsImage,
        current: profile.name == _app.providers?.currentName &&
            model.id == modelLabel,
      ));
    }
  }

  Future<Map<String, List<ModelsDevModel>>> _defaultModelsDevLoader() async {
    final ModelsDevClient client = ModelsDevClient(cachePath: _modelsDevCache());
    try {
      return await client.fetch();
    } finally {
      client.close();
    }
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

  /// 面板 Enter：非「选择来源」模式时，选中新增入口则打开添加流程。
  ///
  /// 「选择来源」模式（[choose] 进行中）由按键层直接 confirm，不进这里。
  Future<void> _confirmProviderItem() async {
    final ProviderRegistry? registry = _app.providers;
    final TuiProviderItem? item = providerPrompt.selected;
    if (registry == null || item == null || !item.isAdd) {
      return;
    }
    providerPrompt.close();
    await _addProvider(registry);
  }

  /// 新增 provider 的「来源选择」列表：知名第三方 / 自定义入口。
  List<TuiProviderItem> sourceItems() => const <TuiProviderItem>[
        TuiProviderItem(
          name: 'Known third-party provider',
          baseUrl: '',
          current: false,
          isKnown: true,
        ),
        TuiProviderItem(
          name: 'Custom registry (api.json)',
          baseUrl: '',
          current: false,
          isCustom: true,
        ),
      ];

  /// 知名第三方 provider 预设列表（选 api_key 后模型清单自动取 models.dev）。
  List<TuiProviderItem> presetItems() => <TuiProviderItem>[
        for (final ProviderPreset preset in kProviderPresets)
          TuiProviderItem(
            name: preset.id,
            baseUrl: preset.baseUrl,
            current: false,
          ),
      ];

  /// 新增 provider：先选来源（知名第三方 / 自定义），再走对应流程。
  ///
  /// 知名第三方再选具体 provider，从 models.dev 拉模型清单供选择；custom 手填
  /// base_url / api_key / model。写回 config.toml；第一个 provider 同时设为
  /// `default_model`（后续不改它）。
  Future<void> _addProvider(ProviderRegistry registry) async {
    final TuiProviderItem? source = await providerPrompt.choose(
      sourceItems(),
      title: 'Add provider',
      hint: '↑↓ navigate · Enter select · Esc cancel',
    );
    if (source == null) {
      transcript.add(TuiRole.system, '已取消新增。');
      return;
    }
    await _continueAdd(registry, source);
  }

  Future<void> _continueAdd(
    ProviderRegistry registry,
    TuiProviderItem source,
  ) async {
    if (source.isCustom) {
      await _addCustomProvider(registry);
      return;
    }
    if (source.isKnown) {
      // 第二级：从预设列表选具体 provider。
      final TuiProviderItem? preset = await providerPrompt.choose(
        presetItems(),
        title: 'Add provider',
        hint: '↑↓ navigate · Enter select · Esc cancel',
      );
      if (preset == null) {
        transcript.add(TuiRole.system, '已取消新增。');
        return;
      }
      await _addRegisteredProvider(registry, preset);
      return;
    }
    await _addRegisteredProvider(registry, source);
  }

  /// custom 入口：手填 base_url / api_key / model（name 可选自动推导）。
  Future<void> _addCustomProvider(ProviderRegistry registry) async {
    final Map<String, String>? values = await formPrompt.ask(TuiFormRequest(
      title: 'Add custom provider',
      hint: '写回 config.toml；第一个 provider 同时设为 default_model。',
      fields: <TuiFormField>[
        TuiFormField(label: 'base_url', placeholder: 'https://api.deepseek.com'),
        TuiFormField(label: 'api_key', obscure: true),
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
    final String apiKey = (values['api_key'] ?? '').trim();
    await _commitProvider(
      registry,
      name: name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      models: <ModelEntry>[ModelEntry(id: model)],
    );
  }

  /// 已注册 provider：只填 api_key，模型清单（带元数据）自动取自 models.dev，
  /// 逐个写入 `[models."<provider>/<model>"]` 段注册进 config.toml。拉取失败
  /// 则只写端点 + key，提示稍后补模型。
  Future<void> _addRegisteredProvider(
    ProviderRegistry registry,
    TuiProviderItem source,
  ) async {
    final Map<String, String>? values = await formPrompt.ask(TuiFormRequest(
      title: 'API key for ${source.name}',
      hint: '模型清单自动取自 models.dev，无需填写 model。',
      fields: <TuiFormField>[
        TuiFormField(label: 'api_key', obscure: true),
      ],
    ));
    if (values == null) {
      transcript.add(TuiRole.system, '已取消新增。');
      return;
    }
    final String apiKey = (values['api_key'] ?? '').trim();
    final List<ModelsDevModel> metas = await _codingModels(source.name);
    if (metas.isEmpty) {
      transcript.add(TuiRole.system, '未能从 models.dev 获取 ${source.name} 的模型清单，'
          '已只写入端点与 api_key；请稍后用 /model 或编辑 config.toml 指定模型。');
    }
    await _commitProvider(
      registry,
      name: source.name,
      baseUrl: source.baseUrl,
      apiKey: apiKey,
      models: <ModelEntry>[
        for (final ModelsDevModel meta in metas)
          ModelEntry(
            id: meta.id,
            displayName: meta.name,
            maxContextSize: meta.contextLength,
            thinking: meta.reasoning,
            toolUse: meta.toolCall,
          ),
      ],
    );
  }

  /// 从 models.dev 取该 provider 过滤后的全部编码可用模型；拉取失败 / 无
  /// 可用模型返回空列表（不打断添加流程）。
  Future<List<ModelsDevModel>> _codingModels(String provider) async {
    final ModelsDevClient client = ModelsDevClient(cachePath: _modelsDevCache());
    try {
      transcript.add(TuiRole.system, '正在从 models.dev 获取 $provider 模型…');
      final Map<String, List<ModelsDevModel>> catalog = await client.fetch();
      return <ModelsDevModel>[
        for (final ModelsDevModel model
            in catalog[provider] ?? const <ModelsDevModel>[])
          if (keepForCoding(model.toolCall, model.reasoning)) model,
      ];
    } on ModelsDevException {
      return const <ModelsDevModel>[];
    } finally {
      client.close();
    }
  }

  /// 写回 config.toml（provider 段 + 逐个 `[models."<p>/<m>"]` 模型段）+ 更新
  /// 内存注册表 + 切换 LLM（统一收尾）。
  Future<void> _commitProvider(
    ProviderRegistry registry, {
    required String name,
    required String baseUrl,
    required String apiKey,
    required List<ModelEntry> models,
  }) async {
    final String? path = _app.get<String>('configPath');
    if (path != null) {
      appendProviderToFile(
        path,
        name: name,
        baseUrl: baseUrl,
        apiKey: apiKey,
        type: 'openai',
        models: models,
        defaultModel: registry.profiles.isEmpty && models.isNotEmpty
            ? '$name/${models.first.id}'
            : null,
      );
    }
    registry.add(ProviderProfile(
      name: name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      models: <String>[for (final ModelEntry entry in models) entry.id],
    ));
    providerPrompt.refresh(providerItems(registry));
    transcript.add(TuiRole.system, '已添加提供商 $name（写入 config.toml）');
    transcript.add(TuiRole.system, await _applyLlm(
        registry, name, model: models.isEmpty ? null : models.first.id));
  }

  /// models.dev 缓存放 config 同目录（如 `~/.nava/models.dev.json`）。
  String? _modelsDevCache() {
    final String? path = _app.get<String>('configPath');
    if (path == null) {
      return null;
    }
    final File file = File(path);
    return '${file.parent.path}${Platform.pathSeparator}models.dev.json';
  }

  /// 启动时回填当前模型的上下文窗口（缓存优先；无缓存/离线保持 0）。
  Future<void> seedModelContextLength() async {
    final ProviderRegistry? registry = _app.providers;
    final String? provider = registry?.currentName;
    if (provider == null || modelLabel.isEmpty) {
      return;
    }
    modelContextLength = await _lookupContextLength(provider, modelLabel);
  }

  /// 异步回填选中模型的上下文窗口（不阻塞切换；查不到保持原值）。
  Future<void> _resolveModelContext(TuiModelItem item) async {
    final int length = item.contextLength > 0
        ? item.contextLength
        : await _lookupContextLength(item.provider, item.model);
    if (length > 0) {
      modelContextLength = length;
      _refresh();
    }
  }

  /// 在 models.dev 目录里查模型的上下文窗口；查不到返回 0。
  Future<int> _lookupContextLength(String provider, String model) async {
    final Future<Map<String, List<ModelsDevModel>>> Function() loader =
        modelsDevLoader ?? _defaultModelsDevLoader;
    try {
      final Map<String, List<ModelsDevModel>> catalog = await loader();
      for (final ModelsDevModel meta
          in catalog[provider] ?? const <ModelsDevModel>[]) {
        if (meta.id == model) {
          return meta.contextLength;
        }
      }
    } on ModelsDevException {
      // 无缓存且离线：状态栏只显示估算值。
    }
    return 0;
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

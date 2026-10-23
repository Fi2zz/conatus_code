/// 把 TOML 顶层表映射为强类型配置。
library;

import 'package:conatus_agent/conatus_agent.dart'
    show
        PermissionEffect,
        PermissionRule,
        normalizePermissionPath,
        permissionActionFor,
        permissionActionUsesPath;

import 'config_schema.dart';
import 'config_values.dart';

/// 结构映射：逐表读取，字段缺失即用默认值，取值非法即抛 [ConfigException]。
class ConfigParser extends ConfigValues {
  ConfigParser(super.raw, super.source);

  /// 解析整份配置。
  ConatusCodeConfig parse() => ConatusCodeConfig(
    llm: _readLlm(),
    providers: _readProviders(),
    models: _readModels(),
    agent: _readAgent(),
    approval: _readApproval(),
    permissions: _readPermissions(),
    sandbox: _readSandbox(),
    budget: _readBudget(),
    credentials: _readCredentials(),
    thinking: _readThinking(),
    services: _readServices(),
    mcp: _readMcp(),
    checkpoint: _readCheckpoint(),
    xerj: _readXerj(),
    hooks: _readHooks(),
    lint: _readLint(),
    formatter: _readFormatter(),
    story: _readStory(),
    background: _readBackground(),
    loopControl: _readLoopControl(),
    tui: _readTui(),
    keybinds: _readKeybinds(),
    defaultPlanMode: readBool(raw, 'default_plan_mode', false),
    extraSkillDirs: readStringList(raw, 'extra_skill_dirs'),
    mergeAllSkills: readBool(raw, 'merge_all_available_skills', false),
    telemetry: readBool(raw, 'telemetry', false),
    instructions: _readInstructions(),
  );

  /// 顶层 `instructions`：路径 / glob / URL 字符串数组；空串过滤掉。
  List<String> _readInstructions() => <String>[
    for (final String entry in readStringList(raw, 'instructions'))
      if (entry.trim().isNotEmpty) entry.trim(),
  ];

  /// 顶层 `default_model`（kimi 风格）优先，回退 `[llm] default_model`。
  LlmConfig _readLlm() {
    final Map<String, dynamic> table = readTable('llm');
    final String? defaultModel =
        readString(raw, 'default_model') ?? readString(table, 'default_model');
    if (defaultModel != null && !_validDefaultModel(defaultModel)) {
      throw ConfigException('$source：default_model 必须是 "provider/model" 形式。');
    }
    return LlmConfig(
      defaultModel: defaultModel,
      fallbackModels: _readFallbackModels(table),
      retry: _readRetry(table),
    );
  }

  /// `[llm] fallback_models`：主模型失败后按序尝试的 `provider/model` 清单。
  List<String> _readFallbackModels(Map<String, dynamic> table) {
    final List<String> entries = <String>[
      for (final String entry in readStringList(table, 'fallback_models'))
        if (entry.trim().isNotEmpty) entry.trim(),
    ];
    for (final String entry in entries) {
      if (!_validDefaultModel(entry)) {
        throw ConfigException(
          '$source：fallback_models 的 "$entry" 必须是 "provider/model" 形式。',
        );
      }
    }
    return entries;
  }

  /// `[llm]` 表里的退避重试参数；缺省即框架侧默认值。
  RetrySettings _readRetry(Map<String, dynamic> table) => RetrySettings(
    maxAttempts: readNonNegativeInt(table, 'max_attempts', 4),
    baseDelayMs: readNonNegativeInt(table, 'retry_base_ms', 500),
    maxDelayMs: readNonNegativeInt(table, 'retry_max_ms', 30000),
  );

  bool _validDefaultModel(String value) {
    final int slash = value.indexOf('/');
    return slash > 0 && slash < value.length - 1;
  }

  List<ProviderConfig> _readProviders() {
    final Map<String, dynamic> table = readTable('providers');
    return <ProviderConfig>[
      for (final MapEntry<String, dynamic> entry in table.entries)
        _readProvider(entry.key, entry.value),
    ];
  }

  ProviderConfig _readProvider(String name, Object? raw) {
    if (raw is! Map) {
      throw ConfigException('$source：providers.$name 必须是表。');
    }
    final Map<String, dynamic> table = raw.cast<String, dynamic>();
    final String baseUrl = readString(table, 'base_url') ?? '';
    if (baseUrl.isEmpty) {
      throw ConfigException('$source：providers.$name.base_url 不能为空。');
    }
    return ProviderConfig(
      name: name,
      baseUrl: baseUrl,
      apiKey: readString(table, 'api_key') ?? '',
      credentialKey: readString(table, 'credential_key') ?? '',
      type: _providerType(table, name),
      oauthKey: _readOauthKey(table, name),
      sessionHeader: readString(table, 'session_header') ?? '',
      userAgent: readString(table, 'user_agent') ?? '',
    );
  }

  ProviderType _providerType(Map<String, dynamic> table, String name) {
    final String? value = readString(table, 'type');
    if (value == null) return ProviderType.openai;
    return switch (value) {
      'openai' => ProviderType.openai,
      'kimi' => ProviderType.kimi,
      'anthropic' => ProviderType.anthropic,
      _ => throw ConfigException(
        '$source：providers.$name.type 取值 "$value" 不合法。',
      ),
    };
  }

  String? _readOauthKey(Map<String, dynamic> table, String name) {
    final Object? oauth = table['oauth'];
    if (oauth == null) return null;
    if (oauth is! Map) {
      throw ConfigException('$source：providers.$name.oauth 必须是表。');
    }
    final Object? key = oauth['key'];
    if (key != null && key is! String) {
      throw ConfigException('$source：providers.$name.oauth.key 必须是字符串。');
    }
    return key as String?;
  }

  AgentConfig _readAgent() {
    final Map<String, dynamic> table = readTable('agent');
    return AgentConfig(
      maxSteps: readPositiveInt(table, 'max_steps', 8),
      workdir: readString(table, 'workdir'),
      projectDir: readString(table, 'project_dir'),
      subagentPermission: _subagentPermission(
        readString(table, 'subagent_permission'),
      ),
      defaultAgent: readString(table, 'default_agent') ?? 'build',
    );
  }

  /// 子代理权限模式：`inherit` / `readonly` / `ask` / `auto`。
  String _subagentPermission(String? value) {
    if (value == null) return 'inherit';
    const Set<String> known = <String>{'inherit', 'readonly', 'ask', 'auto'};
    if (known.contains(value)) return value;
    throw ConfigException(
      '$source：subagent_permission "$value" 不合法（inherit/readonly/ask/auto）。',
    );
  }

  ApprovalConfig _readApproval() {
    final Map<String, dynamic> table = readTable('approval');
    final String? mode =
        readString(raw, 'default_permission_mode') ?? readString(table, 'mode');
    return ApprovalConfig(mode: _approvalMode(mode));
  }

  /// 顶层 `[[permissions]]`：`action` / `resource` / `effect` 三项必填。
  PermissionConfig _readPermissions() {
    final List<Map<String, dynamic>> tables = readTableList('permissions');
    return PermissionConfig(
      rules: <PermissionRule>[
        for (final Map<String, dynamic> table in tables) _readPermission(table),
      ],
    );
  }

  PermissionRule _readPermission(Map<String, dynamic> table) {
    final String action = permissionActionFor(
      _requiredPermissionField(table, 'action'),
    );
    final String resource = _requiredPermissionField(table, 'resource');
    return PermissionRule(
      action: action,
      resource: permissionActionUsesPath(action)
          ? normalizePermissionPath(resource)
          : resource,
      effect: _permissionEffect(_requiredPermissionField(table, 'effect')),
      source: 'config',
    );
  }

  String _requiredPermissionField(Map<String, dynamic> table, String key) {
    final String? value = readString(table, key);
    if (value == null) {
      throw ConfigException('$source：permissions 的 $key 不能为空。');
    }
    return value;
  }

  PermissionEffect _permissionEffect(String value) {
    for (final PermissionEffect effect in PermissionEffect.values) {
      if (effect.name == value) return effect;
    }
    throw ConfigException(
      '$source：permissions 的 effect "$value" 不合法（allow/ask/deny）。',
    );
  }

  SandboxSettings _readSandbox() {
    final Map<String, dynamic> table = readTable('sandbox');
    return SandboxSettings(
      enabled: readBool(table, 'enabled', true),
      fsJail: readBool(table, 'fs_jail', true),
      preset: _sandboxPreset(table),
      allowNetwork: readBool(table, 'allow_network', false),
      networkAllowlist: readStringList(table, 'network_allowlist'),
      allowedExecutables: readStringList(table, 'allowed_executables'),
      writablePaths: readStringList(table, 'writable_paths'),
      commandTimeoutMs: readPositiveInt(table, 'command_timeout_ms', 120000),
      maxOutputBytes: readPositiveInt(table, 'max_output_bytes', 64000),
    );
  }

  BudgetConfig _readBudget() {
    final Map<String, dynamic> table = readTable('budget');
    return BudgetConfig(
      maxTurnSeconds: readBudgetLimit(table, 'max_turn_seconds', 600),
      maxTurnTokens: readBudgetLimit(table, 'max_turn_tokens', 200000),
    );
  }

  Map<String, String> _readCredentials() {
    final Map<String, dynamic> table = readTable('credentials');
    return <String, String>{
      for (final MapEntry<String, dynamic> entry in table.entries)
        entry.key: readListItem('credentials', entry.value),
    };
  }

  List<ModelConfig> _readModels() {
    final Map<String, dynamic> table = readTable('models');
    return <ModelConfig>[
      for (final MapEntry<String, dynamic> entry in table.entries)
        _readModel(entry.key, entry.value),
    ];
  }

  ModelConfig _readModel(String qualifiedName, Object? raw) {
    if (raw is! Map) {
      throw ConfigException('$source：models.$qualifiedName 必须是表。');
    }
    final Map<String, dynamic> table = raw.cast<String, dynamic>();
    final int slash = qualifiedName.indexOf('/');
    final String defaultProvider = slash > 0
        ? qualifiedName.substring(0, slash)
        : '';
    final String defaultModel = slash > 0
        ? qualifiedName.substring(slash + 1)
        : qualifiedName;
    return ModelConfig(
      provider: readString(table, 'provider') ?? defaultProvider,
      model: readString(table, 'model') ?? defaultModel,
      displayName: readString(table, 'display_name') ?? '',
      capabilities: readStringList(table, 'capabilities'),
      maxContext: readNonNegativeInt(table, 'max_context_size', 0),
      maxOutputSize: readNonNegativeInt(table, 'max_output_size', 0),
      reasoningKey: readString(table, 'reasoning_key') ?? '',
      supportEfforts: readStringList(table, 'support_efforts'),
      defaultEffort: readString(table, 'default_effort') ?? '',
      offEffort: readString(table, 'off_effort') ?? '',
      protocol: readString(table, 'protocol') ?? '',
      baseUrl: readString(table, 'base_url') ?? '',
    );
  }

  ThinkingConfig _readThinking() {
    final Map<String, dynamic> table = readTable('thinking');
    return ThinkingConfig(
      enabled: readBool(table, 'enabled', true),
      effort: readString(table, 'effort') ?? '',
    );
  }

  List<ServiceConfig> _readServices() {
    final Map<String, dynamic> table = readTable('services');
    return <ServiceConfig>[
      for (final MapEntry<String, dynamic> entry in table.entries)
        _readService(entry.key, entry.value),
    ];
  }

  ServiceConfig _readService(String name, Object? raw) {
    if (raw is! Map) {
      throw ConfigException('$source：services.$name 必须是表。');
    }
    final Map<String, dynamic> table = raw.cast<String, dynamic>();
    final Object? oauth = table['oauth'];
    String? oauthKey;
    if (oauth is Map) {
      final Object? key = oauth['key'];
      oauthKey = key is String ? key : null;
    }
    return ServiceConfig(
      name: name,
      baseUrl: readString(table, 'base_url') ?? '',
      apiKey: readString(table, 'api_key') ?? '',
      oauthKey: oauthKey,
    );
  }

  McpConfig _readMcp() {
    final Map<String, dynamic> table = readTable('mcp');
    final Object? servers = table['servers'];
    if (servers == null) return const McpConfig();
    if (servers is! Map) {
      throw ConfigException('$source：mcp.servers 必须是表。');
    }
    return McpConfig(
      servers: <McpServerSpec>[
        for (final MapEntry<String, dynamic> entry
            in servers.cast<String, dynamic>().entries)
          _readMcpServer(entry.key, entry.value),
      ],
    );
  }

  McpServerSpec _readMcpServer(String name, Object? raw) {
    if (raw is! Map) {
      throw ConfigException('$source：mcp.servers.$name 必须是表。');
    }
    final Map<String, dynamic> table = raw.cast<String, dynamic>();
    final McpServerType type = _mcpServerType(table, name);
    final String? command = readString(table, 'command');
    final String? url = readString(table, 'url');
    _validateMcpEndpoint(name, type, command, url);
    return McpServerSpec(
      name: name,
      type: type,
      command: command,
      args: readStringList(table, 'args'),
      env: readStringMap(table, 'env', 'mcp.servers.$name.env'),
      url: url,
      headers: readStringMap(table, 'headers', 'mcp.servers.$name.headers'),
    );
  }

  McpServerType _mcpServerType(Map<String, dynamic> table, String name) {
    final String? value = readString(table, 'type');
    if (value == null) return McpServerType.stdio;
    return switch (value) {
      'stdio' => McpServerType.stdio,
      'http' => McpServerType.http,
      'sse' => McpServerType.sse,
      _ => throw ConfigException(
        '$source：mcp.servers.$name.type 取值 "$value" 不合法。',
      ),
    };
  }

  void _validateMcpEndpoint(
    String name,
    McpServerType type,
    String? command,
    String? url,
  ) {
    if (type == McpServerType.stdio && command == null) {
      throw ConfigException(
        '$source：mcp.servers.$name.command 不能为空（stdio 必填）。',
      );
    }
    if (type != McpServerType.stdio && url == null) {
      throw ConfigException('$source：mcp.servers.$name.url 不能为空（http/sse 必填）。');
    }
  }

  CheckpointConfig _readCheckpoint() {
    final Map<String, dynamic> table = readTable('checkpoint');
    return CheckpointConfig(
      enabled: readBool(table, 'enabled', true),
      keep: readNonNegativeInt(table, 'keep', 5),
      ignore: readStringList(table, 'ignore'),
      backend: CheckpointBackend.parse(readString(table, 'backend')),
    );
  }

  XerjConfig _readXerj() {
    final Map<String, dynamic> table = readTable('xerj');
    return XerjConfig(
      enabled: readBool(table, 'enabled', true),
      url: readString(table, 'url') ?? 'http://127.0.0.1:19200',
      dataDir: readString(table, 'data_dir'),
      prefix: readString(table, 'prefix'),
      autoIndex: readBool(table, 'auto_index', true),
    );
  }

  HooksConfig _readHooks() {
    final Map<String, dynamic> table = readTable('hooks');
    return HooksConfig(
      preToolUse: readStringList(table, 'pre_tool_use'),
      postToolUse: readStringList(table, 'post_tool_use'),
      stop: readStringList(table, 'stop'),
    );
  }

  LintConfig _readLint() {
    final Map<String, dynamic> table = readTable('lint');
    return LintConfig(
      enabled: readBool(table, 'enabled', true),
      command: readString(table, 'command'),
      debounceSeconds: readNonNegativeInt(table, 'debounce_seconds', 10),
    );
  }

  FormatterConfig _readFormatter() {
    final Map<String, dynamic> table = readTable('formatter');
    return FormatterConfig(
      // 表存在即视为用户显式启用；表缺失时 enabled 保持 false。
      enabled: readBool(table, 'enabled', raw.containsKey('formatter')),
      command: readString(table, 'command'),
      timeoutMs: readPositiveInt(table, 'timeout_ms', 10000),
      extensions: <String>[
        for (final String extension in readStringList(table, 'extensions'))
          if (extension.trim().isNotEmpty) _formatterExtension(extension),
      ],
    );
  }

  String _formatterExtension(String value) {
    final String trimmed = value.trim().toLowerCase();
    return trimmed.startsWith('.') ? trimmed : '.$trimmed';
  }

  StoryConfig _readStory() {
    final Map<String, dynamic> table = readTable('story');
    return StoryConfig(enabled: readBool(table, 'enabled', false));
  }

  BackgroundConfig _readBackground() {
    final Map<String, dynamic> table = readTable('background');
    return BackgroundConfig(
      keepAliveOnExit: readBool(table, 'keep_alive_on_exit', false),
      maxRunningTasks: readPositiveInt(table, 'max_running_tasks', 4),
    );
  }

  LoopControlConfig _readLoopControl() {
    final Map<String, dynamic> table = readTable('loop_control');
    return LoopControlConfig(
      compactionTriggerRatio: readDouble(
        table,
        'compaction_trigger_ratio',
        0.85,
      ),
      maxStepsPerTurn: readPositiveInt(table, 'max_steps_per_turn', 200),
      reservedContextSize: readPositiveInt(
        table,
        'reserved_context_size',
        50000,
      ),
    );
  }

  TuiConfig _readTui() {
    final Map<String, dynamic> table = readTable('tui');
    return TuiConfig(
      theme: readString(table, 'theme') ?? 'default',
      animations: readBool(table, 'animations', true),
    );
  }

  /// `[keybinds]`：动作 ID → 键位文本。
  ///
  /// 未加引号的 `session.new` 会被 TOML 解析成嵌套表，这里统一摊平成点号键；
  /// `false` 表示关闭动作，映射成 `none`（与字符串写法同义）。
  Map<String, String> _readKeybinds() {
    final Map<String, String> bindings = <String, String>{};
    _flattenKeybinds(readTable('keybinds'), '', bindings);
    return bindings;
  }

  void _flattenKeybinds(
    Map<String, dynamic> table,
    String prefix,
    Map<String, String> out,
  ) {
    for (final MapEntry<String, dynamic> entry in table.entries) {
      final String key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final Object? value = entry.value;
      if (value is Map) {
        _flattenKeybinds(value.cast<String, dynamic>(), key, out);
      } else if (value is String) {
        out[key] = value;
      } else if (value == false) {
        out[key] = 'none';
      } else {
        throw ConfigException('$source：keybinds.$key 必须是字符串或 false。');
      }
    }
  }

  ApprovalMode _approvalMode(String? value) {
    if (value == null) return ApprovalMode.askWhenNeeded;
    return switch (value) {
      'always_ask' || 'alwaysAsk' => ApprovalMode.alwaysAsk,
      'ask_when_needed' ||
      'askWhenNeeded' ||
      'default' ||
      'acceptEdits' ||
      'plan' => ApprovalMode.askWhenNeeded,
      'never_ask' ||
      'neverAsk' ||
      'yolo' ||
      'bypassPermissions' => ApprovalMode.neverAsk,
      _ => throw ConfigException('$source：permission 模式 "$value" 不合法。'),
    };
  }

  SandboxPreset _sandboxPreset(Map<String, dynamic> table) {
    final String? value = readString(table, 'preset');
    if (value == null) return SandboxPreset.workspaceWrite;
    return switch (value) {
      'workspace_write' => SandboxPreset.workspaceWrite,
      'danger_full_access' => SandboxPreset.dangerFullAccess,
      _ => throw ConfigException('$source：sandbox.preset 取值 "$value" 不合法。'),
    };
  }
}

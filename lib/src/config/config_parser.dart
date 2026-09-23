/// 把 TOML 顶层表映射为强类型配置。
library;

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
        sandbox: _readSandbox(),
        budget: _readBudget(),
        credentials: _readCredentials(),
        thinking: _readThinking(),
        services: _readServices(),
        background: _readBackground(),
        loopControl: _readLoopControl(),
        defaultPlanMode: readBool(raw, 'default_plan_mode', false),
        extraSkillDirs: readStringList(raw, 'extra_skill_dirs'),
        mergeAllSkills: readBool(raw, 'merge_all_available_skills', false),
        telemetry: readBool(raw, 'telemetry', false),
      );

  /// 顶层 `default_model`（kimi 风格）优先，回退 `[llm] default_model`。
  LlmConfig _readLlm() {
    final Map<String, dynamic> table = readTable('llm');
    final String? defaultModel =
        readString(raw, 'default_model') ?? readString(table, 'default_model');
    if (defaultModel != null && !_validDefaultModel(defaultModel)) {
      throw ConfigException('$source：default_model 必须是 "provider/model" 形式。');
    }
    return LlmConfig(defaultModel: defaultModel);
  }

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
      type: _providerType(table, name),
      oauthKey: _readOauthKey(table, name),
    );
  }

  ProviderType _providerType(Map<String, dynamic> table, String name) {
    final String? value = readString(table, 'type');
    if (value == null) return ProviderType.openai;
    return switch (value) {
      'openai' => ProviderType.openai,
      'kimi' => ProviderType.kimi,
      _ => throw ConfigException('$source：providers.$name.type 取值 "$value" 不合法。'),
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
      projectDir: readString(table, 'project_dir') ?? '.conatus',
    );
  }

  ApprovalConfig _readApproval() {
    final Map<String, dynamic> table = readTable('approval');
    final String? mode = readString(raw, 'default_permission_mode') ??
        readString(table, 'mode');
    return ApprovalConfig(mode: _approvalMode(mode));
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
    final String defaultProvider =
        slash > 0 ? qualifiedName.substring(0, slash) : '';
    final String defaultModel =
        slash > 0 ? qualifiedName.substring(slash + 1) : qualifiedName;
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
      compactionTriggerRatio:
          readDouble(table, 'compaction_trigger_ratio', 0.85),
      maxStepsPerTurn: readPositiveInt(table, 'max_steps_per_turn', 200),
      reservedContextSize: readPositiveInt(table, 'reserved_context_size', 50000),
    );
  }

  ApprovalMode _approvalMode(String? value) {
    if (value == null) return ApprovalMode.askWhenNeeded;
    return switch (value) {
      'always_ask' || 'alwaysAsk' => ApprovalMode.alwaysAsk,
      'ask_when_needed' || 'askWhenNeeded' || 'default' ||
          'acceptEdits' || 'plan' =>
        ApprovalMode.askWhenNeeded,
      'never_ask' || 'neverAsk' || 'yolo' || 'bypassPermissions' =>
        ApprovalMode.neverAsk,
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

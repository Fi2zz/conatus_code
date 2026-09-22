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
        agent: _readAgent(),
        approval: _readApproval(),
        sandbox: _readSandbox(),
        budget: _readBudget(),
        credentials: _readCredentials(),
      );

  LlmConfig _readLlm() {
    final Map<String, dynamic> table = readTable('llm');
    final String? defaultModel = readString(table, 'default_model');
    if (defaultModel != null && !_validDefaultModel(defaultModel)) {
      throw ConfigException('$source：llm.default_model 必须是 "provider/model" 形式。');
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
    return ApprovalConfig(mode: _approvalMode(table));
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

  ApprovalMode _approvalMode(Map<String, dynamic> table) {
    final String? value = readString(table, 'mode');
    if (value == null) return ApprovalMode.askWhenNeeded;
    return switch (value) {
      'always_ask' => ApprovalMode.alwaysAsk,
      'ask_when_needed' => ApprovalMode.askWhenNeeded,
      'never_ask' => ApprovalMode.neverAsk,
      _ => throw ConfigException('$source：approval.mode 取值 "$value" 不合法。'),
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

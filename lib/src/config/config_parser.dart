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
        agent: _readAgent(),
        approval: _readApproval(),
        sandbox: _readSandbox(),
        credentials: _readCredentials(),
      );

  LlmConfig _readLlm() {
    final Map<String, dynamic> table = readTable('llm');
    return LlmConfig(
      provider: readString(table, 'provider'),
      model: readString(table, 'model'),
    );
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
      enabled: readBool(table, 'enabled', false),
      preset: _sandboxPreset(table),
      allowNetwork: readBool(table, 'allow_network', false),
      networkAllowlist: readStringList(table, 'network_allowlist'),
      allowedExecutables: readStringList(table, 'allowed_executables'),
      commandTimeoutMs: readPositiveInt(table, 'command_timeout_ms', 120000),
      maxOutputBytes: readPositiveInt(table, 'max_output_bytes', 64000),
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

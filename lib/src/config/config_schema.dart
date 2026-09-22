/// conatus_code 的配置模型，对应 `~/.conatus-code/config.toml`。
library;

/// LLM 选择：提供商注册名与模型覆盖。
class LlmConfig {
  const LlmConfig({this.provider, this.model});

  /// `ProviderRegistry` 中的注册名；`null` 表示沿用注册表当前项。
  final String? provider;

  /// 覆盖提供商的默认模型名。
  final String? model;
}

/// Agent Loop 行为。
class AgentConfig {
  const AgentConfig({
    this.maxSteps = 8,
    this.workdir,
    this.projectDir = '.conatus',
  });

  /// 单轮最大步数。
  final int maxSteps;

  /// 工作目录（沙箱根）；`null` 表示当前工作目录。
  final String? workdir;

  /// 项目级状态目录名（会话 / 记忆 / 技能），相对工作目录。
  final String projectDir;
}

/// 审批模式，对应 TUI 的三档权限。
enum ApprovalMode { alwaysAsk, askWhenNeeded, neverAsk }

/// 审批配置。
class ApprovalConfig {
  const ApprovalConfig({this.mode = ApprovalMode.askWhenNeeded});

  /// 缺省「需要时询问」。
  final ApprovalMode mode;
}

/// 沙箱预设。
enum SandboxPreset { workspaceWrite, dangerFullAccess }

/// 沙箱策略；由沙箱层（`src/sandbox/`）消费。
class SandboxSettings {
  const SandboxSettings({
    this.enabled = false,
    this.preset = SandboxPreset.workspaceWrite,
    this.allowNetwork = false,
    this.networkAllowlist = const <String>[],
    this.allowedExecutables = const <String>[],
    this.commandTimeoutMs = 120000,
    this.maxOutputBytes = 64000,
  });

  /// 是否启用沙箱（jail fs + 沙箱命令执行）；缺省关闭。
  final bool enabled;

  /// 缺省「工作区内可写」。
  final SandboxPreset preset;

  /// 命令执行是否放行网络；缺省关闭。
  final bool allowNetwork;

  /// 放行网络的命令前缀白名单（[allowNetwork] 为 false 时生效）。
  final List<String> networkAllowlist;

  /// 可执行文件白名单。
  final List<String> allowedExecutables;

  /// 单条命令的超时上限（毫秒）。
  final int commandTimeoutMs;

  /// 单条命令的输出上限（字节）。
  final int maxOutputBytes;
}

/// 完整配置。
class ConatusCodeConfig {
  const ConatusCodeConfig({
    this.llm = const LlmConfig(),
    this.agent = const AgentConfig(),
    this.approval = const ApprovalConfig(),
    this.sandbox = const SandboxSettings(),
    this.credentials = const <String, String>{},
  });

  final LlmConfig llm;
  final AgentConfig agent;
  final ApprovalConfig approval;
  final SandboxSettings sandbox;

  /// `[credentials]` 表：任意键值，作为凭据来源（环境变量优先）。
  final Map<String, String> credentials;
}

/// conatus_code 的配置模型，对应 `~/.nava/config.toml`。
library;

/// LLM 选择：`provider/model` 同时定当前提供商与默认模型。
class LlmConfig {
  const LlmConfig({this.defaultModel});

  /// `provider/model`（如 `'arkcli-agent-plan/doubao-seed-2-0-lite-260215'`）；
  /// `null` 表示缺省取注册表首个提供商。
  final String? defaultModel;
}

/// provider 类型：决定请求形态（都走 OpenAI 兼容客户端）。
enum ProviderType {
  /// `chat/completions` 形态。
  openai,

  /// `responses` 形态。
  kimi,
}

/// 一个模型提供商的配置（对应 `[providers.<name>]` 表）。
class ProviderConfig {
  const ProviderConfig({
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.type = ProviderType.openai,
    this.oauthKey,
  });

  /// 提供商名（`[providers.<name>]` 的键，可含 `.` / `:`）。
  final String name;

  /// OpenAI 兼容端点根地址。
  final String baseUrl;

  /// API Key；空串表示无 Key。
  final String apiKey;

  /// 请求形态。
  final ProviderType type;

  /// `oauth` 子表的 `key`；保留但不实现 OAuth 调用。
  final String? oauthKey;
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
///
/// 分两层：Layer 1 应用层文件 jail（[fsJail]，防误操作，不依赖 OS 后端）；
/// Layer 2 OS 级沙箱（[enabled]，命令执行经 Seatbelt 隔离，后端不可用时
/// fail-closed 而非降级）。
class SandboxSettings {
  const SandboxSettings({
    this.enabled = true,
    this.fsJail = true,
    this.preset = SandboxPreset.workspaceWrite,
    this.allowNetwork = false,
    this.networkAllowlist = const <String>[],
    this.allowedExecutables = const <String>[],
    this.commandTimeoutMs = 120000,
    this.maxOutputBytes = 64000,
  });

  /// 是否启用 OS 级沙箱（命令执行）；缺省开启。后端不可用时命令执行
  /// fail-closed（注入拒斥执行器，不降级本地 shell）。
  final bool enabled;

  /// 是否启用应用层文件系统 jail（`JailedFileSystem`）；缺省开启。
  /// 纯应用层防误操作，任何平台可用，不依赖 OS 沙箱后端。
  final bool fsJail;

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

/// 预算护栏配置；对应 `[budget]` 表。
class BudgetConfig {
  const BudgetConfig({this.maxTurnSeconds = 600, this.maxTurnTokens = 200000});

  /// 单轮墙钟上限（秒）；`0` 表示不限。
  final int? maxTurnSeconds;

  /// 单轮上下文 token 估算上限；`0` 表示不限。
  final int? maxTurnTokens;
}

/// 完整配置。
class ConatusCodeConfig {
  const ConatusCodeConfig({
    this.llm = const LlmConfig(),
    this.providers = const <ProviderConfig>[],
    this.agent = const AgentConfig(),
    this.approval = const ApprovalConfig(),
    this.sandbox = const SandboxSettings(),
    this.budget = const BudgetConfig(),
    this.credentials = const <String, String>{},
  });

  final LlmConfig llm;

  /// `[providers.<name>]` 表，保持 TOML 书写顺序。
  final List<ProviderConfig> providers;

  final AgentConfig agent;
  final ApprovalConfig approval;
  final SandboxSettings sandbox;
  final BudgetConfig budget;

  /// `[credentials]` 表：任意键值，作为凭据来源（环境变量优先）。
  final Map<String, String> credentials;
}

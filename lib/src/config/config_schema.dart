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
    this.writablePaths = const <String>[],
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

  /// 命令执行是否放行网络；缺省关闭。为 true 时所有命令都不附加网络拒绝规则。
  final bool allowNetwork;

  /// 放行网络的命令前缀白名单（[allowNetwork] 为 false 时生效）。
  final List<String> networkAllowlist;

  /// 可执行文件白名单；与内置缺省集合**合并**（扩展语义，只增不减）。
  final List<String> allowedExecutables;

  /// 额外可写路径（`~` 展开、相对路径基于沙箱根解析），进 Seatbelt 可写根。
  final List<String> writablePaths;

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

/// 一个模型的定义；对应 `[models."<provider>/<model>"]` 表（kimi-code-config
/// 格式：capabilities / display_name / max_context_size / reasoning_key /
/// support_efforts 等）。
class ModelConfig {
  const ModelConfig({
    required this.provider,
    required this.model,
    this.displayName = '',
    this.capabilities = const <String>[],
    this.maxContext = 0,
    this.maxOutputSize = 0,
    this.reasoningKey = '',
    this.supportEfforts = const <String>[],
    this.defaultEffort = '',
    this.offEffort = '',
    this.protocol = '',
    this.baseUrl = '',
  });

  /// 所属提供商（`[providers.<name>]` 的键）。
  final String provider;

  /// API 模型 id。
  final String model;

  /// 展示名。
  final String displayName;

  /// 能力标记（`tool_use` / `image_in` / `always_thinking` 等）。
  final List<String> capabilities;

  /// 上下文窗口（token）；`0` 表示未知。
  final int maxContext;

  /// 最大输出（token）；`0` 表示未知。
  final int maxOutputSize;

  /// 推理内容字段名（如 `reasoning_content`）。
  final String reasoningKey;

  /// 支持的努力级别（`low` / `high` / `max` 等）。
  final List<String> supportEfforts;

  /// 默认努力级别。
  final String defaultEffort;

  /// 关闭推理时的努力级别（如 `none`）。
  final String offEffort;

  /// 请求协议（`openai` / `anthropic`）。
  final String protocol;

  /// 模型级端点覆盖（可空，缺省用 provider 的 `base_url`）。
  final String baseUrl;
}

/// 推理行为；对应 `[thinking]` 表。
class ThinkingConfig {
  const ThinkingConfig({this.enabled = true, this.effort = ''});

  /// 是否启用推理。
  final bool enabled;

  /// 推理努力级别（如 `high`）；空表示用模型默认。
  final String effort;
}

/// 一个外部服务；对应 `[services.<名字>]` 表（搜索 / 抓取等工具的端点）。
class ServiceConfig {
  const ServiceConfig({
    required this.name,
    this.baseUrl = '',
    this.apiKey = '',
    this.oauthKey,
  });

  /// 服务名（`[services.<名字>]` 的键）。
  final String name;

  /// 端点地址。
  final String baseUrl;

  /// API Key。
  final String apiKey;

  /// `oauth` 子表的 `key`（保留字段）。
  final String? oauthKey;
}

/// MCP server 传输类型；对应 `[mcp.servers.<name>].type`。
enum McpServerType {
  /// 本地子进程（`command` + `args`）。
  stdio,

  /// 远程 HTTP 端点（`url`）。
  http,

  /// 远程 SSE 端点（`url`）。
  sse,
}

/// 一台 MCP server 的声明；对应 `[mcp.servers.<name>]` 表。
///
/// [env] 与 [headers] 的值支持 `${KEY}` 凭据占位符，**解析期原样保留**，
/// 装配期经凭据服务替换（替换结果不得写进日志）。
class McpServerSpec {
  const McpServerSpec({
    required this.name,
    required this.type,
    this.command,
    this.args = const <String>[],
    this.env = const <String, String>{},
    this.url,
    this.headers = const <String, String>{},
  });

  /// server 名（`[mcp.servers.<name>]` 的键），兼作工具名前缀（`server__tool`）。
  final String name;

  /// 传输类型。
  final McpServerType type;

  /// `stdio` 的可执行文件；其他类型为 `null`。
  final String? command;

  /// `stdio` 的命令行参数。
  final List<String> args;

  /// `stdio` 注入子进程的环境变量。
  final Map<String, String> env;

  /// `http` / `sse` 的端点地址；`stdio` 为 `null`。
  final String? url;

  /// `http` / `sse` 的附加请求头（如 `Authorization`）。
  final Map<String, String> headers;
}

/// MCP 配置；对应 `[mcp]` 表。
class McpConfig {
  const McpConfig({this.servers = const <McpServerSpec>[]});

  /// `[mcp.servers.<name>]` 表，保持 TOML 书写顺序。
  final List<McpServerSpec> servers;
}

/// 后台任务行为；对应 `[background]` 表（解析保留，供未来执行器消费）。
class BackgroundConfig {
  const BackgroundConfig({
    this.keepAliveOnExit = false,
    this.maxRunningTasks = 4,
  });

  /// 退出时是否保活后台任务。
  final bool keepAliveOnExit;

  /// 并发任务上限。
  final int maxRunningTasks;
}

/// 循环控制；对应 `[loop_control]` 表（解析保留，供未来压缩/步数消费）。
class LoopControlConfig {
  const LoopControlConfig({
    this.compactionTriggerRatio = 0.85,
    this.maxStepsPerTurn = 200,
    this.reservedContextSize = 50000,
  });

  /// 压缩触发比例。
  final double compactionTriggerRatio;

  /// 单轮最大步数。
  final int maxStepsPerTurn;

  /// 预留上下文（token）。
  final int reservedContextSize;
}

/// 完整配置。
class ConatusCodeConfig {
  const ConatusCodeConfig({
    this.llm = const LlmConfig(),
    this.providers = const <ProviderConfig>[],
    this.models = const <ModelConfig>[],
    this.agent = const AgentConfig(),
    this.approval = const ApprovalConfig(),
    this.sandbox = const SandboxSettings(),
    this.budget = const BudgetConfig(),
    this.credentials = const <String, String>{},
    this.thinking = const ThinkingConfig(),
    this.services = const <ServiceConfig>[],
    this.mcp = const McpConfig(),
    this.background = const BackgroundConfig(),
    this.loopControl = const LoopControlConfig(),
    this.defaultPlanMode = false,
    this.extraSkillDirs = const <String>[],
    this.mergeAllSkills = false,
    this.telemetry = false,
  });

  final LlmConfig llm;

  /// `[providers.<name>]` 表，保持 TOML 书写顺序。
  final List<ProviderConfig> providers;

  /// `[models."<provider>/<model>"]` 表：显式模型定义（覆盖内置目录）。
  final List<ModelConfig> models;

  final AgentConfig agent;
  final ApprovalConfig approval;
  final SandboxSettings sandbox;
  final BudgetConfig budget;

  /// `[credentials]` 表：任意键值，作为凭据来源（环境变量优先）。
  final Map<String, String> credentials;

  /// `[thinking]` 表。
  final ThinkingConfig thinking;

  /// `[services.<名字>]` 表。
  final List<ServiceConfig> services;

  /// `[mcp]` 表。
  final McpConfig mcp;

  /// `[background]` 表。
  final BackgroundConfig background;

  /// `[loop_control]` 表。
  final LoopControlConfig loopControl;

  /// 顶层 `default_plan_mode`：启动时默认进入 Plan Mode。
  final bool defaultPlanMode;

  /// 顶层 `extra_skill_dirs`：额外技能目录。
  final List<String> extraSkillDirs;

  /// 顶层 `merge_all_available_skills`：合并全部可用技能。
  final bool mergeAllSkills;

  /// 顶层 `telemetry`：遥测开关。
  final bool telemetry;
}

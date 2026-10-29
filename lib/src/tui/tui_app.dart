/// conatus TUI 的运行时装配：把基础设施、Agent Loop 依赖与会话持久化接好。
///
/// 这是一个独立的 [Context] 根，所有服务都随 [dispose] 一并释放。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_harness/conatus_harness.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:conatus_memory/conatus_memory.dart';
import 'package:conatus_search/conatus_search.dart';
import 'package:conatus_skill/conatus_skill.dart';

import '../../fs_tools.dart';
import '../../providers.dart';
import '../../xerj.dart';
import '../agents/agent_registry.dart';
import '../agents/agent_resolver.dart';
import '../assembly/permission_mode.dart';
import '../background/background_tasks.dart';
import '../background/background_tools.dart';
import '../budget/budgeted_llm.dart';
import '../budget/cost_tracker.dart';
import '../budget/turn_budget.dart';
import '../checkpoint/checkpoint_backend.dart';
import '../checkpoint/checkpoint_manager.dart';
import '../commands/command_registry.dart';
import '../config/config_path.dart';
import '../config/config_schema.dart';
import '../format/formatter_service.dart';
import '../hooks/hooks.dart';
import '../instructions/instruction_loader.dart';
import '../instructions/instruction_prompt.dart';
import '../instructions/instruction_wiring.dart';
import '../lint/linter.dart';
import '../lsp/lsp_manager.dart';
import '../lsp/lsp_navigation.dart';
import '../lsp/lsp_navigation_tools.dart';
import '../lsp/lsp_tool.dart';
import '../mcp/mcp_assembly.dart';
import '../mcp/mcp_prompt_commands.dart';
import '../permissions/permission_wiring.dart';
import '../project/project_registry.dart';
import '../project/worktree_service.dart';
import '../references/references.dart';
import '../subagent/subagent_progress.dart';
import '../subagent/swarm_member.dart';
import '../tools/code_tools.dart';
import '../tools/command_policy.dart';
import '../tools/custom_tools.dart';
import '../tools/guarded_shell.dart';
import 'ask_user_tool.dart';
import 'system_notifier.dart';
import 'tui_choice.dart';
import 'tui_controller.dart';
import 'tui_permission.dart';
import 'tui_permission_gate.dart';

/// conatus TUI 运行时：持有根 [Context] 与已装配的服务。
/// 解析工作目录的真实路径；失败（目录不存在等）时原样返回。
///
/// macOS 上 `/tmp`、`/var` 都是 `/private/...` 的别名，而 bin 传给 fs jail 的根是
/// 规范化过的。溢出目录若用未规范化的拼写，jail 在目标父链尚不存在时无法解析符号
/// 链接、退回字符串前缀比对，就会把合法路径误判为越界。
String _canonicalize(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return path;
  }
}

/// 持久化「总是允许」规则；失败时把原因作为系统提示上屏。
Future<void> _rememberPermissionRules(
  Context app,
  PermissionWiring wiring,
  List<PermissionRule> rules,
  List<String> resources,
) async {
  final ConatusTuiController? controller = app.get<ConatusTuiController>(
    'tuiController',
  );
  if (controller != null) {
    await controller.rememberPermissionRules(rules, resources);
    return;
  }
  // 没有控制器（库用法）时仍然落盘，只是没有屏上提示。
  await wiring.remember(rules, resources);
}

class ConatusTuiRuntime {
  ConatusTuiRuntime._({
    required this.app,
    required this.sessions,
    required this.tools,
    required this.modelLabel,
    required this.providers,
    required this.maxSteps,
    required this.fallbackModels,
    required this.retryPolicy,
    required this.storyEnabled,
    required this.lspManager,
    required void Function(FallbackLlm llm) switchLlm,
  }) : _switchLlm = switchLlm;

  /// 根上下文。
  final Context app;

  /// 会话仓库。
  final SessionStore sessions;

  /// 工具注册表。
  final ToolRegistry tools;

  /// 顶栏展示的模型标签。
  final String modelLabel;

  /// 提供商注册表；`providers: false` 时为 `null`（`/provider` 不可用）。
  final ProviderRegistry? providers;

  /// Agent Loop 单轮最大步数。
  final int maxSteps;

  /// 配置里的回退链；`/model` 切换主模型后仍跟随（见 `llm_chain.dart`）。
  final List<String> fallbackModels;

  /// 单个提供商内部的退避重试策略。
  final RetryPolicy retryPolicy;

  /// 是否装配故事层（`[story] enabled`）。
  final bool storyEnabled;

  /// 已启用的 LSP 管理器；未启用为 null。
  final LspManager? lspManager;

  final void Function(FallbackLlm llm) _switchLlm;

  /// 运行时替换 LLM 提供商（`/model`、`/provider` 切换用）。
  ///
  /// 只换根上下文的服务；已绑定的会话仍持有旧提供商，需再调
  /// [ConatusTuiController.rebind] 重建 Agent Loop 才生效。
  void switchLlm(FallbackLlm llm) => _switchLlm(llm);

  /// 装配一个默认运行时。
  ///
  /// [sessionDir] / [memoryFile] / cron 任务与运行历史缺省落在 [baseDir]
  /// （缺省由项目注册表解析到 `$NAVA_HOME/workspaces/<basename>-<hash>`，
  /// 不在工作区内）下；[webTools] 为 true 时按 `kDefaultSearchOrder`
  /// 装配搜索源（缺 Key 的自动跳过，见 `conatus_search`）；[skills] 为 true 时
  /// 从 `.conatus/skills` 等目录
  /// 发现技能，注入目录段并注册 `skill` 工具。
  /// [llm] 缺省用注册表当前提供商构造的实例（[model] 覆盖其默认模型名，见
  /// `lib/providers.dart`）；显式传入则以传入者为准（如 DeepSeek-only 的 Demo）。
  /// 没有缺省回退链：两者都拿不到时抛 [StateError]。[modelLabel] 覆盖顶栏模型标签。
  ///
  /// [providers] 传配置的 `[providers.*]` 列表时装配提供商注册表（`/provider`
  /// 命令据此可用）；[provider] 定当前提供商（`[llm] default_model` 的
  /// `provider/model` 拆分）。[models] 传 `[models."provider/model"]` 清单时按
  /// provider 名填入各 profile 的模型 id 列表（`/model` 浮层候选）。
  ///
  /// [fs] / [shell] / [credentials] 是能力接缝的注入点：缺省用本地实现
  /// （`LocalFileSystem` / `LocalShellExecutor` / `EnvCredentials`）。沙箱层经
  /// 它们换成受限实现；`fs` 工具与 `rg` 都会跟随（`rg` 从上下文取 `'shell'`）。
  /// [mcpTransportFactory] 是 MCP 传输的测试注入点（缺省按配置分派）。
  /// [commandHome] 覆盖命令发现的家目录（测试注入假 home；缺省读环境变量）。
  /// [shellInteractive] 是用户直发命令（`!` shell 模式）的交互缝，缺省本地直执
  /// 不经命令白名单；模型发起的命令仍走 [shell]（沙箱照常）。
  /// [turnBudget] 为每轮预算护栏（缺省 10 分钟墙钟 + 模型窗口 75% 的估算
  /// token）；传 `TurnBudget(maxDuration: null, maxTokens: null)` 可关闭。
  /// [interactive] 为 `false` 时跳过人机交互件（浮层 / 审批服务 / `ask_user`
  /// 工具），供 headless 单轮执行使用。
  ///
  /// 显式 [baseDir] 会绕过项目注册表；若同时传入 [projectRegistry]，该
  /// registry 被忽略且由调用方负责关闭。
  /// [defaultAgent] 是新会话默认 Agent（`[agent] default_agent`）；未知或仅子
  /// Agent 的定义回退到注册表默认的 `build`。
  /// [instructions] 是顶层 `instructions` 的额外来源（路径 / glob / URL），
  /// 追加在项目 `AGENTS.md` 之后；[instructionHome] 覆盖用户级全局文件的
  /// 家目录（测试注入假 home，缺省读 `HOME`）。
  // REASON: 装配入口的参数聚合是既定形态（本参数已 20 个），调用方是进程级
  // main，不存在逐层透传问题。
  static Future<ConatusTuiRuntime> create({
    String? sessionDir,
    String? memoryFile,
    String? baseDir,
    ProjectRegistry? projectRegistry,
    String? projectDir,
    String? configPath,
    bool webTools = true,
    bool skills = true,
    List<String> extraSkillDirs = const <String>[],
    bool mergeAllSkills = false,
    List<ProviderConfig>? providers,
    List<ModelConfig>? models,
    String? provider,
    String? model,
    int maxSteps = 8,
    SubAgentPermission subagentPermission = SubAgentPermission.inherit,
    String? defaultAgent,
    FallbackLlm? llm,
    RetryPolicy? retryPolicy,
    List<String> fallbackModels = const <String>[],
    TurnBudget? turnBudget,
    LspConfig lsp = const LspConfig(),
    String? modelLabel,
    FileSystem? fs,
    ShellExecutor? shell,
    ShellExecutor? shellInteractive,
    Credentials? credentials,
    List<McpServerSpec>? mcpServers,
    List<CustomToolConfig> customTools = const <CustomToolConfig>[],
    McpTransport Function(McpServerConfig config)? mcpTransportFactory,
    String? commandHome,
    bool interactive = true,
    String? workdir,
    CheckpointConfig? checkpoint,
    XerjConfig? xerj,
    BackgroundConfig? background,
    HooksConfig? hooks,
    LintConfig? lint,
    FormatterConfig? formatter,
    StoryConfig? story,
    PermissionConfig? permissions,
    ApprovalMode approvalMode = ApprovalMode.askWhenNeeded,
    List<String> instructions = const <String>[],
    List<String> configWarnings = const <String>[],
    List<ResolvedReference> references = const <ResolvedReference>[],
    String? instructionHome,
    HarnessManifest? harness,
  }) async {
    final bool storyEnabled = story?.enabled ?? false;
    final Context app = Context.root(name: 'conatus');
    final String sep = Platform.pathSeparator;
    final String resolvedWorkdir = workdir ?? Directory.current.path;
    // 规范化形式：与 bin 传给 fs jail 的根保持同一拼写。解析失败（如目录不存在）
    // 时退回原值——后续 fs 操作会给出更具体的报错。
    final String canonicalWorkdir = _canonicalize(resolvedWorkdir);
    final String resolvedBaseDir;
    final WorkspaceInfo? projectInfo;
    final ProjectRegistry? projectRegistryService;
    if (baseDir != null) {
      resolvedBaseDir = baseDir;
      projectInfo = null;
      projectRegistryService = null;
    } else {
      projectRegistryService = projectRegistry ?? ProjectRegistry.open();
      projectInfo = projectRegistryService.resolve(
        resolvedWorkdir,
        dataDirOverride: projectDir,
      );
      resolvedBaseDir = projectInfo.dataDir;
    }

    // ── 工具：时间 / 回显 / 文件读取 / 联网（可选）──────────────
    provideTools(app, timeout: const Duration(seconds: 30));
    app.effect(
      () => app.tools.fn(
        'get_time',
        description: '返回当前本地时间（RFC 3339，带时区偏移）',
        handler: (ToolContext ctx) async {
          final DateTime now = DateTime.now();
          return ToolResult.success(
            '${now.toIso8601String()}'
            '${formatClockOffset(now.timeZoneOffset)}',
          );
        },
      ),
    );
    app.effect(
      () => app.tools.fn(
        'echo',
        description: '回显输入文本',
        params: <ParamSpec>[ParamSpec.string('text', required: true)],
        handler: (ToolContext ctx) async => ToolResult.success(ctx.str('text')),
      ),
    );

    // ── 权限：最外层工具中间件 ──────────────────────────────────
    // 必须在 hooks / 结果驱逐 / lint / story 之前注册：那些中间件能短路调用，
    // 晚注册就会让权限规则看不到被拦下的调用。会话切换只换槽位里的作用域
    // （见 ConatusTuiController._syncPermissionMode），这里挂一次即可。
    final PermissionWiring permissionWiring = PermissionWiring(
      store: PermissionStore('$resolvedBaseDir${sep}permissions.json'),
      workdir: canonicalWorkdir,
      configRules: permissions?.rules ?? const <PermissionRule>[],
    );
    await permissionWiring.load();
    // 交互模式下阈值等控制器绑定会话后再设（`_syncPermissionMode`）：没有
    // 控制器的库用法（只建 runtime 直接调工具）与旧行为一致——不弹审批。
    // headless 没有绑定时机，配置里的 `[approval] mode` 直接落到这里。
    permissionWiring.applyMode(
      askThreshold: interactive
          ? null
          : toTuiPermissionMode(approvalMode).threshold,
      agentId: 'build',
    );
    app.provide('permissionWiring', permissionWiring);
    app.provide(kPermissionScopeService, permissionWiring.slot);
    // 工作区边界判定用规范化路径：相对 `--workdir` 也能正确比较绝对目标。
    app.provide('permissionWorkdir', canonicalWorkdir);
    instrumentPermission(app, interactive: interactive);

    provideTelemetry(app);
    instrumentTools(app);

    // `.opencode`（项目级 + 全局）是用户 OpenCode 自己的目录：nava 只做兼容
    // 读取，绝不创建 / 写入 / 删除。闸门包在 fs 接缝上，write_file /
    // edit_file / apply_patch / story 写回等一切经 'fs' 的写操作自动继承
    // （见 read_only_path_guard.dart）；读操作透传。
    //
    // 受保护根同时用字面 workdir 与规范 workdir 两种拼写：`--workdir /tmp/x`
    // 经符号链接（macOS `/var` → `/private/var`）时，模型看到的 displayPath
    // 与 CLI 的 fs 根可能各用一种；闸门内部还会对根补规范拼写（根尚不存在时
    // 沿最近已存在祖先解析），两层一起挡住「首次写就创建 `.opencode`」。
    // 未注入 fs 时以 workdir 为相对路径基准：否则 `create(workdir: X)` 的
    // 相对写入会落到进程 cwd，既不符合直觉，也让闸门按另一棵树判定。
    provideFileSystemLocal(
      app,
      fs: ReadOnlyPathGuard(
        inner: fs ?? LocalFileSystem(cwd: resolvedWorkdir),
        protectedRoots: <String>{
          ...defaultReadOnlyRoots(resolvedWorkdir),
          ...defaultReadOnlyRoots(canonicalWorkdir),
        }.toList(),
      ),
    );
    // 'shell' 既是 rg 的必需依赖（fs 工具回落到 ctx.get('shell')），也是命令执行
    // 的唯一接缝：注入受限实现后 rg / run_command / run_tests / run_code 一并跟随。
    // 命令形状审查：本地直执外面套一层 command_shield 分析。REVIEW 的人工
    // 复核回调在下面的审批装配里接线；headless 未接线即按拒绝（fail-closed）。
    final GuardedShellExecutor guardedShell = shell is GuardedShellExecutor
        ? shell
        : GuardedShellExecutor(
            inner: shell ?? LocalShellExecutor(),
            policy: CommandPolicy(),
          );
    provideShellLocal(app, executor: guardedShell);
    // 'shellInteractive'：用户直发命令（`!` shell 模式）的交互缝——本地直执、
    // 不过模型命令审查（对齐 OpenCode）；模型命令仍走上面的 'shell' 缝。
    app.provide('shellInteractive', shellInteractive ?? LocalShellExecutor());
    provideFsTools(app);
    LspManager? lspManager;
    if (lsp.enabled) {
      final LspManager manager = LspManager(
        config: lsp,
        workdir: canonicalWorkdir,
      );
      lspManager = manager;
      app.provide('lsp', manager);
      app.effect(() => app.tools.register(LspDiagnosticsTool(source: manager)));
      app.effect(
        () => app.tools.use(lspDiagnosticsMiddleware(manager), tag: 'lsp'),
      );
      final LspNavigator navigator = LspNavigator(manager);
      for (final Tool tool in <Tool>[
        LspHoverTool(navigator, manager),
        LspDefinitionTool(navigator, manager),
        LspReferencesTool(navigator, manager),
        LspDocumentSymbolsTool(navigator, manager),
      ]) {
        app.effect(() => app.tools.register(tool));
      }
      app.onDispose(() {
        unawaited(manager.close());
      });
    }
    // XERJ 代码检索（可选外部二进制）：找不到 xerj 时 provide 返回空列表，
    // 工具面与未启用完全一致。节点懒启动、数据目录在工作区之外。
    final XerjConfig xerjConfig = xerj ?? const XerjConfig();
    if (xerjConfig.enabled) {
      provideXerjSearch(
        app,
        options: XerjOptions(
          workdir: canonicalWorkdir,
          url: xerjConfig.url,
          dataDir: xerjConfig.dataDir ?? '${resolveConfigDir()}$sep$xerj',
          prefix: xerjConfig.prefix,
          autoIndex: xerjConfig.autoIndex,
        ),
      );
    }
    // 溢出目录必须落在工作目录内（fs jail 以工作目录为根，而溢出预览要让模型
    // 用 read_file 读回来，见 spill_dir.dart）。且必须用**规范化**路径：jail 在
    // 目标父链尚不存在时无法解析符号链接，退回字符串前缀比对，而 jail 的根是
    // 规范化过的 —— macOS 上 /var → /private/var、/tmp → /private/tmp 这种别名
    // 会让首次写入被误判越界。
    provideToolResultEviction(app, dir: toolResultSpillDir(canonicalWorkdir));
    // conatus_code 自己的工具：list_files / git_status / git_diff（M3 起再加
    // run_command / run_tests / apply_patch）。同样跟随上面的 fs / shell 接缝。
    provideCodeTools(app);

    // ── 交互：选项浮层 + 审批端口（headless 不装）────────────────
    // 浮层状态挂在根上下文：控制器构造时接上重绘回调，审批与 `ask_user`
    // 共用同一条提问通道。权限中间件已在上面根上下文最外层挂好（见
    // `instrumentPermission`）；这里只提供 `Approval` 端口，控制器绑定会话时
    // 只更新作用域槽位，不再重挂中间件。
    // `interactive: false`（headless）跳过全部人机交互件：无浮层、无审批
    // 服务、无 ask_user 工具——需要询问的调用由权限中间件按
    // `PERMISSION_ASK_UNATTENDED` 拒绝（沙箱仍是执行层底线）。
    if (interactive) {
      final TuiChoicePrompt choice = TuiChoicePrompt();
      app.provide('tuiChoice', choice);
      final TuiPermissionGate gate = TuiPermissionGate(
        choice: choice,
        fs: app.get<FileSystem>('fs'),
        // 「总是允许」落盘到项目 permissions.json；失败只提示，不撤销本次放行。
        rememberRules: (List<PermissionRule> rules, List<String> resources) {
          unawaited(
            _rememberPermissionRules(app, permissionWiring, rules, resources),
          );
        },
      );
      provideApproval(
        app,
        approval: gate,
        // 权限中间件只用这里的 `Approval` 端口处理 ask；阈值由控制器写入
        // 作用域槽位（见 ConatusTuiController._syncPermissionMode），不再
        // 挂第二层审批中间件。
        instrument: false,
      );
      // 命令 REVIEW → 同一选项浮层征询人工复核；headless 不接线（按拒绝，
      // fail-closed）。NeverAsk 视同放行，与其余审批语义一致。
      guardedShell.reviewPrompter = (String command, String reason) async {
        if (gate.mode == TuiPermissionMode.neverAsk) return true;
        final String? picked = await choice.ask(
          TuiChoiceRequest(
            title: '命令需人工复核',
            choices: <TuiChoice>[
              TuiChoice(
                id: 'command-review-allow',
                label: '允许执行',
                description: '$command\n复核理由：$reason',
              ),
              const TuiChoice(
                id: 'command-review-deny',
                label: '拒绝',
                description: '不执行，把拒绝结果回给模型。',
              ),
            ],
          ),
          timeout: kTuiDecisionTimeout,
        );
        return picked == 'command-review-allow';
      };
      app.effect(
        () => app.tools.register(
          AskUserTool(host: () => app.get<TuiUserPromptHost>('tuiController')),
        ),
      );
    }

    // ── 凭据（先于联网工具：搜索源要经凭据服务解析 Key）──────────
    // Key 统一经凭据服务：provider、注册表与搜索源都不直接读环境变量，换
    // config.toml / File / Vault 等来源时只改这一处注入。缺省 EnvCredentials。
    final Credentials resolvedCredentials = provideCredentials(
      app,
      credentials: credentials,
    );

    if (webTools) {
      provideSearch(app, credentials: resolvedCredentials);
      provideWebTools(app, credentials: resolvedCredentials);
    }

    // ── 声明式自定义工具（[[tools]]）────────────────────────────
    // 用户显式配置的 CLI / HTTP 受信端；默认 high 风险，进审批。
    if (customTools.isNotEmpty) {
      provideCustomTools(
        app,
        tools: customTools,
        workdir: resolvedWorkdir,
        credentials: resolvedCredentials,
      );
    }

    // ── MCP server（config.toml [mcp.servers.*]）─────────────────
    // 逐台挂载、单台失败跳过；工具经 server__tool 前缀进注册表，高危走审批。
    final McpRegistry? mcpRegistry = await attachMcpServers(
      app,
      mcpServers ?? const <McpServerSpec>[],
      credentials: resolvedCredentials,
      transportFactory: mcpTransportFactory,
    );
    // 资源清单 / 读取是本地内置工具：挂上注册表即对模型可见（只读、低风险）。
    if (mcpRegistry != null) {
      provideMcpResourceTools(app, registry: mcpRegistry);
    }

    // ── 模型 / 自省 / 子 Agent ─────────────────────────────────
    // `[models."provider/model"]`（kimi 格式）按 provider 名展开成模型 id 清单，
    // 供 `/model` 浮层候选与 registry 默认模型使用；没有该表时清单为空。
    final Map<String, List<String>> modelsByProvider = <String, List<String>>{};
    for (final ModelConfig config in models ?? const <ModelConfig>[]) {
      modelsByProvider
          .putIfAbsent(config.provider, () => <String>[])
          .add(config.model);
    }
    ProviderRegistry? registry;
    if (providers != null) {
      registry = provideProviders(
        app,
        providers: <ProviderProfile>[
          for (final ProviderConfig config in providers)
            ProviderProfile(
              name: config.name,
              baseUrl: config.baseUrl,
              apiKey: config.apiKey,
              credentialKey: config.credentialKey,
              apiStyle: switch (config.type) {
                ProviderType.kimi => LlmApiStyle.responses,
                ProviderType.anthropic => LlmApiStyle.anthropic,
                ProviderType.openai => LlmApiStyle.chat,
              },
              models: modelsByProvider[config.name] ?? const <String>[],
              sessionHeader: config.sessionHeader,
              userAgent: config.userAgent,
            ),
        ],
        currentName: provider,
        credentials: resolvedCredentials,
      );
      for (final ProviderConfig config in providers) {
        if (config.apiKey.isEmpty && config.oauthKey != null) {
          // REASON: 走 stderr 而非 stdout——headless `--output-format json` 要求
          // stdout 只有可解析的单行 JSON，启动警告写 stdout 会让 jq 失败。
          stderr.writeln('OAuth 未实现：请为 ${config.name} 配置 api_key。');
        }
      }
    }
    if (provider != null && registry != null && registry.profiles.isNotEmpty) {
      if (registry.byName(provider) == null) {
        throw StateError('未知提供商：$provider（config.toml [providers] 里没有）');
      }
    }

    // LLM 链：主模型 + `[llm] fallback_models`，每个候选各包一层退避重试。
    // 提示出口挂到上下文，控制器订阅后写进屏上记录（见 LlmNotices）。
    final LlmNotices notices = LlmNotices();
    app.provide('llmNotices', notices);
    app.onDispose(notices.close);
    final List<String> chainEntries = <String>[
      if (model != null && model.isNotEmpty)
        '$provider/$model'
      else if (provider != null)
        provider,
      ...fallbackModels,
    ];
    final LlmChain? chain = registry == null
        ? null
        : buildLlmChain(
            registry,
            entries: chainEntries,
            policy: retryPolicy ?? const RetryPolicy(),
            notices: notices,
          );

    // 模型档案（上下文窗口 + 真实费率）：先给空索引、后台预热，拿到后广播。
    // 冷启动不等网络——冷缓存下这一下可达 30s，而窗口/价格拿不到时一切照常，
    // 只是状态栏与 `/cost` 显示「未知」。
    final ModelProfileStore modelProfiles = ModelProfileStore(
      cachePath: _modelsDevCachePath(configPath),
    );
    app.provide('modelProfiles', modelProfiles);
    app.onDispose(modelProfiles.close);
    unawaited(modelProfiles.warmUp());

    // 预算护栏：包装 `'llm'` 服务（每轮墙钟 + 上下文 token 估算），并把首个
    // CostTracker 实现注册到 `'costTracker'`（供未来 autonomous runner 消费）。
    final CostTrackerImpl costTracker = CostTrackerImpl(
      store: modelProfiles,
      provider: provider ?? registry?.currentName,
      model: model,
    );
    app.provide('costTracker', costTracker);
    final TurnBudget resolvedBudget = turnBudget ?? const TurnBudget();
    if (configPath != null) {
      app.provide('configPath', configPath);
    }
    if (llm == null && chain == null) {
      // 无配置：注入占位 provider，TUI 照常启动并引导添加（不报错退出）。
      app.provide('providerSetupNeeded', true);
    }
    final FallbackLlm resolvedLlm =
        llm ??
        chain?.llm ??
        FallbackLlm(<LlmProvider>[_UnconfiguredProvider()]);
    // 换模型时不能重复 provide（服务键唯一，重复会抛 StateError），所以放可替换槽位。
    app.provide('llmChainSlot', LlmChainSlot(chain));
    Disposer llmDisposer = provideBudgetedLlm(
      app,
      llm: resolvedLlm,
      budget: resolvedBudget,
      costTracker: costTracker,
    );
    void switchLlm(FallbackLlm next) {
      llmDisposer();
      llmDisposer = provideBudgetedLlm(
        app,
        llm: next,
        budget: resolvedBudget,
        costTracker: costTracker,
      );
    }

    provideReflection(app);

    // ── 自定义 Agent：发现 + spawn_agent 的 profile 解析 ──────────
    final AgentRegistry agentRegistry = await AgentRegistry.load(
      workdir: resolvedWorkdir,
      defaultId: defaultAgent,
    );
    app.provide('agentRegistry', agentRegistry);
    // 自定义命令：只读发现，`.opencode` 仅读取不写入（见 CommandRegistry）。
    final CommandRegistry commandRegistry = await CommandRegistry.load(
      workdir: resolvedWorkdir,
      home: commandHome,
    );
    // MCP prompt → `/<server>:<prompt>`；同名磁盘命令优先，不覆盖已发现定义。
    if (mcpRegistry != null) {
      registerMcpPromptCommands(
        commandRegistry,
        await loadMcpPromptCommands(mcpRegistry, onWarning: stderr.writeln),
      );
    }
    app.provide('commandRegistry', commandRegistry);
    app.provide('definitionRoots', <String>[
      ...AgentRegistry.roots(workdir: resolvedWorkdir, home: commandHome),
      ...CommandRegistry.roots(workdir: resolvedWorkdir, home: commandHome),
    ]);
    final AgentProfileResolver agentProfiles = AgentProfileResolver(
      registry: agentRegistry,
      providers: registry,
    );
    // `/doctor` 与启动提示读取解析器的告警（未知 / 非法 model 回退）。
    app.provide('agentProfiles', agentProfiles);
    app.onDispose(agentProfiles.close);
    // 启动时即校验 Agent 的 model，让坏配置当场可见而不是等到 spawn。
    await agentProfiles.validateModels();

    // 子 Agent：进度出口 + **独立的轮次预算**。
    //
    // `llm` 传未包装的 resolvedLlm，让每个子 Agent 拿一个自己计数的新
    // BudgetedLlmProvider：否则子 Agent 那十几轮调用会全记进**主**轮次，把
    // 主轮次撞爆 max_turn_tokens 提前收口，而子 Agent 的半截结论会被当成结论
    // 回传。成本仍记进同一个 costTracker（那部分是真实花费）。
    final SubAgentProgressStore subagentProgress = SubAgentProgressStore();
    app.provide('subagentProgress', subagentProgress);
    app.onDispose(subagentProgress.close);
    // 泳道投影：子 Agent 的活动也进团队视图（它不在 AgentTeam 里，故直接写
    // 订阅的泳道表）。`sink` 要等控制器订阅团队后才接得上，故用可后设的出口。
    final SwarmProjection swarm = SwarmProjection();
    app.provide('swarmProjection', swarm);
    provideSpawnAgent(
      app,
      llm: resolvedLlm,
      // 两个出口都接：对话视图的逐行提示 + 团队视图的泳道。
      onProgress: (SubAgentEvent e) {
        subagentProgress.report(e);
        swarm.report(e);
      },
      childLlm: (LlmProvider base) => BudgetedLlmProvider(
        base,
        budget: resolvedBudget,
        costTracker: costTracker,
      ),
      // 默认只读探索集：子 Agent 无人看管，默认不给写 / 执行类（write_file 等
      // 是 medium、run_command 等是 high；high 在框架层已被 `_allowedTools`
      // 挡掉，这里再把 medium 写操作排除）。rg/glob/list_files 是定位文件的
      // 入口——缺了它们，模型没显式传 tools 时子 Agent 只能读已知路径。
      defaultTools: const <String>[
        'get_time',
        'echo',
        'read_file',
        'rg',
        'glob',
        'list_files',
        'git_status',
        'git_diff',
      ],
      permissionMode: subagentPermission,
      profileResolver: agentProfiles,
    );

    // ── 后台任务：消费 [background] 配置与 'shell' 的 start() 能力缝 ──
    // 服务跨会话存活；命令照常过沙箱（CommandPolicy + seatbelt）。退出时
    // 按 keep_alive_on_exit 终止（缺省）或保活脱离。
    final BackgroundTaskService backgroundTasks = BackgroundTaskService(
      shell: app.require<ShellExecutor>('shell'),
      maxRunningTasks: background?.maxRunningTasks ?? 4,
      keepAliveOnExit: background?.keepAliveOnExit ?? false,
    );
    app.provide('backgroundTasks', backgroundTasks);
    provideBackgroundTools(app, service: backgroundTasks);
    app.onDispose(backgroundTasks.shutdown);

    // ── Hooks：Pre/Post 挂工具中间件，Stop 由控制器 _afterTurn 触发 ──
    if (hooks != null) {
      provideHooks(app, config: hooks);
    }
    // ── lint-on-edit：模型编辑后自动跑 linter 并闭环 ──
    if (lint != null) {
      provideLinter(app, config: lint, workdir: resolvedWorkdir);
    }
    // ── format-on-edit：在 linter 之后挂（更内层），先格式化再交给 linter ──
    if (formatter != null) {
      provideFormatter(app, config: formatter, workdir: resolvedWorkdir);
    }
    // ── 会话持久化（JSONL）+ 会话仓库 ────────────────────────────
    provideSessionPersistence(
      app,
      persistence: JsonlSessionPersistence(
        dir: sessionDir ?? '$resolvedBaseDir${sep}sessions',
      ),
    );
    final SessionStore sessions = provideSessions(app);
    // 故事层日志（doc/* 事件）：启用时才装配服务（关闭时零副作用）。
    // 目录本身始终登记：删除会话时即使故事层已关闭，也要能找到并清掉历史
    // 故事线文件（见 `_clearSessionArtifacts`）。
    final String storyLogDir = '$resolvedBaseDir${sep}story-log';
    app.provide('storyLogDir', storyLogDir);
    if (storyEnabled) {
      provideSessionLog(
        app,
        persistence: JsonlSessionPersistence(dir: storyLogDir),
      );
    }

    // ── system prompt / 记忆 / 压缩 / 技能 ──────────────────────
    final SystemPrompt prompt = provideSystemPrompt(app);
    // permissions.json 载入失败时 deny 规则会静默消失：把这件事写进系统提示
    // （模型与用户都会看到），并在 `/doctor` 里再报一次。
    final String? permissionLoadError = permissionWiring.loadError;
    if (permissionLoadError != null) {
      prompt.section(
        PromptSection(
          name: 'permission-warning',
          text: () =>
              '权限规则未载入：$permissionLoadError。'
              '当前只有 config 规则与兜底阈值生效，不要假设项目级 deny 仍在。',
        ),
      );
    }
    prompt.section(
      PromptSection(
        name: 'persona',
        text: () => '你是"助手"，一位耐心、务实的助手。需要实时信息或操作时调用工具；否则直接简洁回答。',
      ),
    );
    prompt.section(
      PromptSection(
        name: 'coding',
        text: () =>
            '编码任务先规划后执行：复杂任务先用 plan_write 制定执行计划，'
            '执行中每完成一步用 update_plan 标记进度；工具失败时反思原因并重试或调整方案。',
      ),
    );
    if (storyEnabled && interactive) {
      prompt.section(
        PromptSection(
          name: 'story-ops',
          text: () =>
              '文件编辑（write_file / edit_file / apply_patch）默认进入待定审阅：'
              '人接受后才真正落盘。收到「已登记为待定补丁」的结果后继续推进或等待，'
              '不要重试同一编辑。也可以用 ```ops 围栏块（JSON 数组的块操作）提议修改。',
        ),
      );
    }
    prompt.section(
      PromptSection(
        name: 'steering',
        text: () => '用户可能在你工作途中插话：出现新的用户消息时，优先响应最新要求。',
      ),
    );
    // 项目指令：全局 AGENTS.md → 项目根 → 工作目录 → 嵌套 → `instructions`
    // （见 instructions/）。`project` 段的 text provider 每次 assemble 都会触发
    // 重新装配，工具的嵌套发现因此下一轮即生效；注入 `'workdir'` 服务供
    // `/init` 等命令定位仓库根。
    app.provide('workdir', resolvedWorkdir);
    app.provide('projectDataDir', resolvedBaseDir);
    if (projectInfo != null) {
      app.provide('projectInfo', projectInfo);
    }
    if (projectRegistryService != null) {
      app.provide('projectRegistry', projectRegistryService);
      app.provide(
        'worktreeService',
        WorktreeService(
          registry: projectRegistryService,
          workdir: resolvedWorkdir,
        ),
      );
      app.onDispose(projectRegistryService.close);
    }
    app.provide('configWarnings', configWarnings);
    final InstructionLoader instructionLoader = provideInstructionLoader(
      app,
      workdir: resolvedWorkdir,
      home: instructionHome,
      extra: instructions,
    );
    final InstructionPrompt instructionPrompt = InstructionPrompt(
      loader: instructionLoader,
      prompt: prompt,
    );
    await instructionPrompt.start();
    app.effect(
      () => instrumentInstructionNotes(
        app,
        instructionLoader,
        onNoted: instructionPrompt.refresh,
      ),
    );
    // 检查点：每轮收口后快照工作区（见 checkpoint_manager.dart）。数据目录
    // 取 baseDir（缺省 ~/.nava/workspaces/<basename>-<hash>，不在工作区内），快照/
    // 恢复走 dart:io 直连。
    if (checkpoint != null) {
      app.provide(
        'checkpointManager',
        CheckpointManager(
          store: await openCheckpointStore(
            config: checkpoint,
            root: resolvedWorkdir,
            projectDir: Directory(resolvedBaseDir).absolute.path,
          ),
          config: checkpoint,
        ),
      );
    }
    provideTimePrompt(app);
    provideReferencePrompt(app, references);
    provideMemory(
      app,
      backend: JsonMemoryBackend(
        file: File(memoryFile ?? '$resolvedBaseDir${sep}memory.json'),
      ),
    );
    provideMemoryTools(app);
    provideMemoryRecorder(app);
    provideCompaction(app);
    provideSkillLibrary(app);
    if (skills) {
      await provideSkillRegistry(app);
      provideSkillCatalog(app, includeAll: mergeAllSkills);
      provideSkillTool(app, includeAll: mergeAllSkills);
      await provideSkillFilesystem(
        app,
        roots: _skillRoots(resolvedWorkdir, extraSkillDirs),
      );
    }

    // ── 恢复：数据库（JSON 后端，集中在 baseDir）+ 快照服务 ─────────
    provideDatabase(app, defaultBackend: 'json');
    provideDatabaseJson(app, dir: '$resolvedBaseDir${sep}database');
    provideRecovery(app);

    // ── cron 定时任务：全局任务表 + 运行历史 + 到点交付 ─────────
    provideCron(
      app,
      storage: JsonCronStorage(
        tasksPath: '$resolvedBaseDir${sep}cron-tasks.json',
        historyPath: '$resolvedBaseDir${sep}cron-history.jsonl',
      ),
    );
    provideCronTools(app);
    provideCronRuntime(
      app,
      deliver: (String recordId, String framing, CronTask task) async {
        final ConatusTuiController? controller = app.get<ConatusTuiController>(
          'tuiController',
        );
        if (controller == null) return false;
        return controller.deliverCron(recordId, framing);
      },
      options: CronRuntimeOptions(notifier: systemCronNotifier()),
    );

    if (harness != null) applyHarness(app, harness);

    return ConatusTuiRuntime._(
      app: app,
      sessions: sessions,
      tools: app.tools,
      modelLabel:
          modelLabel ?? model ?? _modelLabel(registry, resolvedCredentials),
      providers: registry,
      maxSteps: maxSteps,
      fallbackModels: fallbackModels,
      retryPolicy: retryPolicy ?? const RetryPolicy(),
      storyEnabled: storyEnabled,
      lspManager: lspManager,
      switchLlm: switchLlm,
    );
  }

  /// 构造一个绑定到 [initialSession] 的会话控制器。
  ///
  /// [initialSession] 是要打开/恢复的会话 id；`null`（缺省）表示新建会话。
  /// [initialPermissionMode] 是会话自身没有权限记录时采用的模式（来自配置）。
  ConatusTuiController createController({
    String? initialSession,
    required void Function() onExit,
    void Function(String workdir)? onSwitchProject,
    String name = '默认',
    bool planning = false,
    TuiPermissionMode initialPermissionMode = TuiPermissionMode.askWhenNeeded,
    Map<String, String> keybinds = const <String, String>{},
  }) {
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: name,
      initialSession: initialSession,
      modelLabel: modelLabel,
      maxSteps: maxSteps,
      planning: planning,
      onExit: onExit,
      onSwitchProject: onSwitchProject,
      initialPermissionMode: initialPermissionMode,
      fallbackModels: fallbackModels,
      retryPolicy: retryPolicy,
      storyEnabled: storyEnabled,
      keybinds: keybinds,
    );
    controller.switchLlm = switchLlm;
    return controller;
  }

  /// 结束运行时：等待在途写入落定后释放根上下文。
  Future<void> dispose() async {
    await lspManager?.close();
    await sessions.flush();
    app.dispose();
  }

  static String _modelLabel(
    ProviderRegistry? registry,
    Credentials credentials,
  ) {
    final String? model = registry?.current?.defaultModel;
    if (model != null) return model;
    if (credentials.get('ARK_API_KEY') != null) return 'doubao-seed-1-8-251228';
    if (credentials.get('DEEPSEEK_API_KEY') != null) return 'deepseek-flash';
    return '未配置（设置 ARK_API_KEY / DEEPSEEK_API_KEY）';
  }

  /// models.dev 缓存放 config 同目录（如 `~/.nava/models.dev.json`）。
  static String? _modelsDevCachePath(String? configPath) {
    if (configPath == null) return null;
    final File file = File(configPath);
    return '${file.parent.path}${Platform.pathSeparator}models.dev.json';
  }
}

/// 未配置任何 provider 时的占位：任何调用都提示去配置。
class _UnconfiguredProvider implements LlmProvider {
  @override
  String get name => 'unconfigured';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async => LlmResult(
    content: '尚未配置模型提供商：用 /provider 添加，或编辑 ~/.nava/config.toml。',
    provider: name,
    model: 'none',
  );

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 默认发现根 + 配置里的 `extra_skill_dirs`（相对 workdir / `~` 展开）。
List<SkillRoot> _skillRoots(String workdir, List<String> extra) {
  final List<SkillRoot> roots = defaultSkillRoots(
    projectRoot: findProjectRoot(from: workdir),
  );
  final Set<String> seen = <String>{
    for (final SkillRoot root in roots) root.path,
  };
  for (final String raw in extra) {
    final String? path = _extraSkillDir(raw, workdir);
    if (path == null || !seen.add(path)) continue;
    roots.add(SkillRoot(path: path, source: kSkillSourceCustom, rank: 300));
  }
  return roots;
}

String? _extraSkillDir(String raw, String workdir) {
  final String value = raw.trim();
  if (value.isEmpty) return null;
  if (value == '~') return resolveHomeDir();
  if (value.startsWith('~/')) {
    return '${resolveHomeDir()}/${value.substring(2)}';
  }
  if (value.startsWith('/')) return value;
  return '$workdir${Platform.pathSeparator}$value';
}

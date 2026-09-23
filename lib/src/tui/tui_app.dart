/// conatus TUI 的运行时装配：把基础设施、Agent Loop 依赖与会话持久化接好。
///
/// 这是一个独立的 [Context] 根，所有服务都随 [dispose] 一并释放。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_search/conatus_search.dart';
import 'package:conatus_skill/conatus_skill.dart';

import '../../fs_tools.dart';
import '../../providers.dart';
import '../budget/budgeted_llm.dart';
import '../budget/cost_tracker.dart';
import '../budget/turn_budget.dart';
import '../config/config_schema.dart';
import '../tools/code_tools.dart';
import 'ask_user_tool.dart';
import 'system_notifier.dart';
import 'tui_choice.dart';
import 'tui_controller.dart';
import 'tui_permission.dart';
import 'tui_permission_gate.dart';

/// conatus TUI 运行时：持有根 [Context] 与已装配的服务。
class ConatusTuiRuntime {
  ConatusTuiRuntime._({
    required this.app,
    required this.sessions,
    required this.tools,
    required this.modelLabel,
    required this.providers,
    required this.maxSteps,
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

  final void Function(FallbackLlm llm) _switchLlm;

  /// 运行时替换 LLM 提供商（`/model`、`/provider` 切换用）。
  ///
  /// 只换根上下文的服务；已绑定的会话仍持有旧提供商，需再调
  /// [ConatusTuiController.rebind] 重建 Agent Loop 才生效。
  void switchLlm(FallbackLlm llm) => _switchLlm(llm);

  /// 装配一个默认运行时。
  ///
  /// [sessionDir] / [memoryFile] / cron 任务与运行历史缺省落在 [baseDir]
  /// （默认 `<cwd>/.conatus`）下；[webTools] 为 true 时按 `kDefaultSearchOrder`
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
  /// [turnBudget] 为每轮预算护栏（缺省宽松启用：10 分钟墙钟 + 20 万估算
  /// token）；传 `TurnBudget(maxDuration: null, maxTokens: null)` 可关闭。
  // REASON: 装配入口的参数聚合是既定形态（本参数已 16 个），调用方是进程级
  // main，不存在逐层透传问题。
  static Future<ConatusTuiRuntime> create({
    String? sessionDir,
    String? memoryFile,
    String? baseDir,
    String? configPath,
    bool webTools = true,
    bool skills = true,
    List<ProviderConfig>? providers,
    List<ModelConfig>? models,
    String? provider,
    String? model,
    int maxSteps = 8,
    FallbackLlm? llm,
    TurnBudget? turnBudget,
    String? modelLabel,
    FileSystem? fs,
    ShellExecutor? shell,
    Credentials? credentials,
  }) async {
    final Context app = Context.root(name: 'conatus');
    final String resolvedBaseDir =
        baseDir ?? '${Directory.current.path}${Platform.pathSeparator}.conatus';
    final String sep = Platform.pathSeparator;

    // ── 工具：时间 / 回显 / 文件读取 / 联网（可选）──────────────
    provideTools(app, timeout: const Duration(seconds: 30));
    app.effect(() => app.tools.fn(
          'get_time',
          description: '返回当前本地时间（RFC 3339，带时区偏移）',
          handler: (ToolContext ctx) async {
            final DateTime now = DateTime.now();
            return ToolResult.success('${now.toIso8601String()}'
                '${formatClockOffset(now.timeZoneOffset)}');
          },
        ));
    app.effect(() => app.tools.fn(
          'echo',
          description: '回显输入文本',
          params: <ParamSpec>[ParamSpec.string('text', required: true)],
          handler: (ToolContext ctx) async =>
              ToolResult.success(ctx.str('text')),
        ));

    provideTelemetry(app);
    instrumentTools(app);

    provideFileSystemLocal(app, fs: fs);
    // 'shell' 既是 rg 的必需依赖（fs 工具回落到 ctx.get('shell')），也是命令执行
    // 的唯一接缝：注入受限实现后 rg / run_command / run_tests / run_code 一并跟随。
    provideShellLocal(app, executor: shell);
    provideFsTools(app);
    provideToolResultEviction(app);
    // conatus_code 自己的工具：list_files / git_status / git_diff（M3 起再加
    // run_command / run_tests / apply_patch）。同样跟随上面的 fs / shell 接缝。
    provideCodeTools(app);

    // ── 交互：选项浮层 + 工具审批 ────────────────────────────────
    // 浮层状态挂在根上下文：控制器构造时接上重绘回调，审批与 `ask_user`
    // 共用同一条提问通道。审批中间件不在这里装——它随权限模式在控制器里
    // 挂载 / 卸载（见 ConatusTuiController._syncPermissionMode）。
    final TuiChoicePrompt choice = TuiChoicePrompt();
    app.provide('tuiChoice', choice);
    provideApproval(
      app,
      approval: TuiPermissionGate(
        choice: choice,
        fs: app.get<FileSystem>('fs'),
      ),
      // 拦截阈值随权限模式变化，由控制器按需挂载 / 卸载
      // （见 ConatusTuiController._syncPermissionMode），这里只提供服务。
      instrument: false,
    );
    app.effect(() => app.tools.register(AskUserTool(
          host: () => app.get<TuiUserPromptHost>('tuiController'),
        )));

    // ── 凭据（先于联网工具：搜索源要经凭据服务解析 Key）──────────
    // Key 统一经凭据服务：provider、注册表与搜索源都不直接读环境变量，换
    // config.toml / File / Vault 等来源时只改这一处注入。缺省 EnvCredentials。
    final Credentials resolvedCredentials =
        provideCredentials(app, credentials: credentials);

    if (webTools) {
      provideSearch(app, credentials: resolvedCredentials);
      provideWebTools(app, credentials: resolvedCredentials);
    }

    // ── 模型 / 自省 / 子 Agent ─────────────────────────────────
    // `[models."provider/model"]`（kimi 格式）按 provider 名展开成模型 id 清单，
    // 供 `/model` 浮层候选与 registry 默认模型使用；没有该表时清单为空。
    final Map<String, List<String>> modelsByProvider = <String, List<String>>{};
    for (final ModelConfig config in models ?? const <ModelConfig>[]) {
      modelsByProvider.putIfAbsent(config.provider, () => <String>[]).add(config.model);
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
              apiStyle: config.type == ProviderType.kimi
                  ? LlmApiStyle.responses
                  : LlmApiStyle.chat,
              models: modelsByProvider[config.name] ?? const <String>[],
            ),
        ],
        currentName: provider,
        credentials: resolvedCredentials,
      );
      for (final ProviderConfig config in providers) {
        if (config.apiKey.isEmpty && config.oauthKey != null) {
          // REASON: 启动提示走 stdout，与其它装配警告一致（OAuth 未实现，
          // 该 provider 不可用但其余照常）。
          print('OAuth 未实现：请为 ${config.name} 配置 api_key。');
        }
      }
    }
    if (provider != null && registry != null && registry.profiles.isNotEmpty) {
      if (registry.byName(provider) == null) {
        throw StateError('未知提供商：$provider（config.toml [providers] 里没有）');
      }
    }
    final LlmProvider? fromRegistry = registry?.buildLlm(
      provider ?? registry.currentName ?? '',
      model: model,
    );
    // 预算护栏：包装 `'llm'` 服务（每轮墙钟 + 上下文 token 估算），并把首个
    // CostTracker 实现注册到 `'costTracker'`（供未来 autonomous runner 消费）。
    final CostTrackerImpl costTracker = CostTrackerImpl();
    app.provide('costTracker', costTracker);
    final TurnBudget resolvedBudget = turnBudget ?? const TurnBudget();
    if (configPath != null) {
      app.provide('configPath', configPath);
    }
    if (llm == null && fromRegistry == null) {
      // 无配置：注入占位 provider，TUI 照常启动并引导添加（不报错退出）。
      app.provide('providerSetupNeeded', true);
    }
    final FallbackLlm resolvedLlm = llm ??
        (fromRegistry != null
            ? FallbackLlm(<LlmProvider>[fromRegistry])
            : FallbackLlm(<LlmProvider>[_UnconfiguredProvider()]));
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
    provideSpawnAgent(
      app,
      defaultTools: <String>['get_time', 'echo', 'read_file'],
    );

    // ── 会话持久化（JSONL）+ 会话仓库 ────────────────────────────
    provideSessionPersistence(
      app,
      persistence: JsonlSessionPersistence(
        dir: sessionDir ?? '$resolvedBaseDir${sep}sessions',
      ),
    );
    final SessionStore sessions = provideSessions(app);

    // ── system prompt / 记忆 / 压缩 / 技能 ──────────────────────
    final SystemPrompt prompt = provideSystemPrompt(app);
    prompt.section(PromptSection(
      name: 'persona',
      text: () => '你是"助手"，一位耐心、务实的助手。需要实时信息或操作时调用工具；否则直接简洁回答。',
    ));
    prompt.section(PromptSection(
      name: 'coding',
      text: () => '编码任务先规划后执行：复杂任务先用 plan_write 制定执行计划，'
          '执行中每完成一步用 update_plan 标记进度；工具失败时反思原因并重试或调整方案。',
    ));
    provideTimePrompt(app);
    provideMemory(
      app,
      backend: JsonMemoryBackend(
        file: File(memoryFile ?? '$resolvedBaseDir${sep}memory.json'),
      ),
    );
    provideMemoryTools(app);
    provideCompaction(app);
    provideSkillLibrary(app);
    if (skills) {
      await provideSkillRegistry(app);
      provideSkillCatalog(app);
      provideSkillTool(app);
      await provideSkillFilesystem(app);
    }

    // ── 恢复：数据库（JSON 后端）+ 快照服务 ────────────────────
    provideDatabase(app, defaultBackend: 'json');
    provideDatabaseJson(app);
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
        final ConatusTuiController? controller =
            app.get<ConatusTuiController>('tuiController');
        if (controller == null) return false;
        return controller.deliverCron(recordId, framing);
      },
      options: CronRuntimeOptions(notifier: systemCronNotifier()),
    );

    return ConatusTuiRuntime._(
      app: app,
      sessions: sessions,
      tools: app.tools,
      modelLabel: modelLabel ?? model ?? _modelLabel(registry, resolvedCredentials),
      providers: registry,
      maxSteps: maxSteps,
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
    String name = '默认',
    TuiPermissionMode initialPermissionMode = TuiPermissionMode.askWhenNeeded,
  }) {
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: name,
      initialSession: initialSession,
      modelLabel: modelLabel,
      maxSteps: maxSteps,
      onExit: onExit,
      initialPermissionMode: initialPermissionMode,
    );
    controller.switchLlm = switchLlm;
    return controller;
  }

  /// 结束运行时：等待在途写入落定后释放根上下文。
  Future<void> dispose() async {
    await sessions.flush();
    app.dispose();
  }

  static String _modelLabel(ProviderRegistry? registry, Credentials credentials) {
    final String? model = registry?.current?.defaultModel;
    if (model != null) return model;
    if (credentials.get('ARK_API_KEY') != null) return 'doubao-seed-1-8-251228';
    if (credentials.get('DEEPSEEK_API_KEY') != null) return 'deepseek-flash';
    return '未配置（设置 ARK_API_KEY / DEEPSEEK_API_KEY）';
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
  }) async =>
      LlmResult(
        content: '尚未配置模型提供商：用 /provider 添加，或编辑 ~/.nava/config.toml。',
        provider: name,
        model: 'none',
      );

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

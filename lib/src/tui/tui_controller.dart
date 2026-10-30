/// TUI 会话控制器：把 conatus 的 [Context] / [SessionStore] / Agent Loop 桥接到
/// nocterm 组件，处理斜杠命令、会话切换与屏上记录的投射。
///
/// 设计要点：一个有界子上下文（`plugin('tui-session:<id>')`）承载当前会话的
/// Agent Loop —— 切换会话即释放旧子上下文、建立新子上下文，效应随上下文自动
/// 撤销，无需手工清理。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:conatus_diff/conatus_diff.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:conatus_schedule/conatus_schedule.dart';
import 'package:conatus_search/conatus_search.dart';
import 'package:conatus_skill/conatus_skill.dart';
import 'package:conatus_team/conatus_team.dart';

import '../../providers.dart';
import '../agents/agent_definition.dart';
import '../agents/agent_picker.dart';
import '../agents/agent_registry.dart';
import '../agents/agent_resolver.dart';
import '../autonomous/autonomous_assembly.dart';
import '../background/background_tasks.dart';
import '../budget/budgeted_llm.dart';
import '../budget/cost_tracker.dart';
import '../checkpoint/checkpoint_manager.dart';
import '../checkpoint/checkpoint_types.dart';
import '../commands/command_definition.dart';
import '../commands/command_dispatcher.dart';
import '../commands/command_registry.dart';
import '../config/config_path.dart';
import '../config/config_writer.dart';
import '../config/project_data_dir.dart';
import '../diagnose/doctor.dart';
import '../diff/diff_source.dart';
import '../hooks/hooks.dart';
import '../lsp/lsp_manager.dart';
import '../permissions/permission_wiring.dart';
import '../project/project_database.dart';
import '../project/project_registry.dart';
import '../project/worktree_service.dart';
import '../revert/revert_compensate.dart';
import '../revert/revert_service.dart';
import '../revert/revert_stage.dart';
import '../story/story.dart';
import '../story/story_commands.dart';
import '../story/story_notices.dart';
import '../story/story_pending.dart';
import '../story/story_render.dart';
import '../subagent/subagent_progress.dart';
import '../subagent/swarm_member.dart';
import '../tabs/tab_manager.dart';
import '../tools/update_plan.dart';
import '../version.dart';
import 'ask_user_tool.dart';
import 'at_ref.dart';
import 'definition_watcher.dart';
import 'keymap/keymap.dart';
import 'keymap/keymap_view.dart';
import 'session_exporter.dart';
import 'session_ui_state.dart';
import 'settings_prompt.dart';
import 'team_snapshot.dart';
import 'team_subscription.dart';
import 'theme/nava_theme.dart';
import 'theme/theme_view.dart';
import 'trace_renderer.dart';
import 'transcript.dart';
import 'tui_agent_selection.dart';
import 'tui_attachment.dart';
import 'tui_choice.dart';
import 'tui_commands.dart';
import 'tui_form.dart';
import 'tui_help.dart';
import 'tui_message.dart';
import 'tui_model.dart';
import 'tui_options.dart';
import 'tui_permission.dart';
import 'tui_permission_gate.dart';
import 'tui_permission_prompt.dart';
import 'tui_plan.dart';
import 'tui_provider.dart';
import 'tui_rename_view.dart';
import 'tui_session_picker.dart';
import 'tui_skill_command.dart';

part 'tui_controller_provider.dart';
part 'tui_controller_redo.dart';
part 'tui_controller_revert.dart';

/// `/goal` 用法提示。
const String kGoalUsage =
    '用法：/goal [status|set <文本>|edit <文本>|pause|resume|done|clear]';

/// `/story` 用法提示。
const String kStoryUsage =
    '用法：/story（时间轴）| preview <n>（前 n 个补丁时刻）| discard <n>（驳回并写回）|'
    ' fork <n>（从前 n 个补丁分叉新会话）| pending（待定补丁）| apply <i>（接受）|'
    ' reject <i>（丢弃）';

/// `/cron` 用法提示。
const String kCronUsage =
    '用法：/cron [list|add <内容> <at|every|daily|cron> <规则>|'
    'remove <id>|enable <id>|disable <id>|history [条数]]\n'
    '规则：at=ISO 时刻；every=秒或 10分钟/1小时；daily/每天=HH:MM；'
    '每周X=HH:MM；cron=5 段表达式';

/// `/team` 用法提示。
const String kTeamUsage = '用法：/team（进入团队视图）[status|interrupt <成员 id>]';

/// `/task` 用法提示。
const String kTaskUsage = '用法：/task [claim <任务 id>|release <任务 id>]';

/// `/diff` 用法提示。
const String kDiffUsage = '用法：/diff [working|turn]（缺省 working；只读，不写工作区）';

/// `/background` 用法提示。
const String kBackgroundUsage =
    '用法：/background [list|output <任务 id>|kill <任务 id>]';

/// 消息队列容量上限（busy 时排队追问）。
const int kMessageQueueCap = 20;

/// `!` shell 命令的默认超时（毫秒）。
const int kShellBangTimeoutMs = 60000;

/// 自定义命令 shell 块失败时最多展示的字符数（避免整段日志刷屏）。
const int kCommandFailureLimit = 2000;

/// `/compact` 的手动压缩保留条数：小于自动预算，强制折叠较早历史。
const int kManualCompactKeepRecent = 20;

/// TUI 会话控制器。
class ConatusTuiController implements TuiUserPromptHost {
  ConatusTuiController({
    required Context app,
    required SessionStore sessions,
    required this.name,
    String? initialSession,
    required this.modelLabel,
    this.maxSteps = 8,
    this.planning = false,
    this.onExit,
    this.onSwitchProject,
    this.initialPermissionMode = TuiPermissionMode.askWhenNeeded,
    this.startInPlanMode = false,
    this.storyEnabled = false,
    this.initialAgentId,
    List<String> fallbackModels = const <String>[],
    RetryPolicy retryPolicy = const RetryPolicy(),
    this.keybinds = const <String, String>{},
  }) : _app = app,
       _sessions = sessions,
       _sessionId = initialSession ?? '',
       _newSessionAtStart = initialSession == null,
       _fallbackModels = fallbackModels,
       _retryPolicy = retryPolicy {
    picker = TuiSessionPicker(
      sessions,
      onChanged: _refresh,
      onLoadError: _reportSessionLoadError,
    );
    _app.provide('tuiController', this);
    final TuiPermissionGate? gate = app.get<TuiPermissionGate>('approval');
    _gate = gate;
    choice.onChanged = _refresh;
    _watchLlmNotices();
    _watchSubagent();
    _syncPermissionMode();
  }

  /// 订阅 LLM 韧性提示并即时上屏。
  ///
  /// 退避重试可能静默 30 秒——没有这行提示，用户看到的是一个不动的转圈。
  void _watchLlmNotices() {
    final LlmNotices? notices = _app.get<LlmNotices>('llmNotices');
    if (notices == null) return;
    _noticeSubscription = notices.stream.listen((LlmNotice notice) {
      transcript.add(TuiRole.system, notice.text);
      _refresh();
    });
  }

  /// 订阅子 Agent 进度并即时上屏。
  ///
  /// 子 Agent 一次能跑几十秒，期间主链路在 `await` 里完全静止。看不到它调了
  /// 什么工具，用户既判断不了它有没有跑偏，也不敢中途打断。
  void _watchSubagent() {
    final SubAgentProgressStore? store = _app.get<SubAgentProgressStore>(
      'subagentProgress',
    );
    if (store == null) return;
    _subagentSub = store.lines.listen((SubAgentLine line) {
      transcript.add(TuiRole.stage, line.text);
      _refresh();
    });
  }

  final Context _app;
  final SessionStore _sessions;

  /// 是否装配故事层（`[story] enabled`）。
  final bool storyEnabled;

  /// 启动时指定的 Agent ID；空 / 未知 / 仅子 Agent 时回退到注册表默认值。
  final String? initialAgentId;

  /// `[keybinds]` 原始配置；[keymap] 据此合成（缺省动作用内置默认值）。
  final Map<String, String> keybinds;

  /// 合成后的全局键位表；根组件与 `/keybinds` 共用同一份。
  late final Keymap keymap = Keymap.fromConfig(keybinds);

  /// 当前会话 Agent ID（`/agents` 切换后更新）。
  String _agentId = 'build';

  /// 首次绑定（启动）用 `initialAgentId` / 配置默认值；之后的新会话一律用
  /// `[agent] default_agent`，不继承上一个标签的选择。
  bool _firstBind = true;

  /// 本次重绑临时指定的 Agent（自定义命令覆盖）；非空时优先于会话事件。
  String? _bindAgentOverride;

  /// 当前 Agent 注入的 system prompt 段撤销函数。
  Disposer? _agentPromptDisposer;

  /// 自定义命令临时覆盖的还原点（本轮结束后在 [_afterTurn] 还原）。
  _TurnOverride? _turnOverride;

  /// 非 Agent 指定、由配置 / `/model` 决定的模型基线。
  ///
  /// 切到没有 `model:` 的 Agent 时恢复到它，避免继承上一个 Agent 的模型。
  _ModelChoice? _modelBaseline;

  /// 前台子 Agent 命令的打断入口（Esc 调用）；空闲时为 `null`。
  void Function()? _foregroundInterrupt;

  /// 配置里的回退链（`[llm] fallback_models`）；`/model` 切换主模型后仍跟随。
  final List<String> _fallbackModels;

  /// 单个提供商内部的退避重试策略。
  final RetryPolicy _retryPolicy;

  /// LLM 重试 / 回退的提示订阅；控制器销毁时随 `_unbind` 一并取消。
  StreamSubscription<LlmNotice>? _noticeSubscription;

  /// models.dev 档案就绪通知；用来在冷启动拉到数据后补上上下文窗口。
  StreamSubscription<void>? _modelProfileSub;

  /// 子 Agent 进度订阅；控制器销毁时取消。
  StreamSubscription<SubAgentLine>? _subagentSub;

  /// 选项浮层（`question` 与工具审批共用）。
  ///
  /// 优先复用根上下文里已提供的 `'tuiChoice'`（审批门持有的是同一个），
  /// 未提供时自建一个。
  @override
  late final TuiChoicePrompt choice =
      _app.get<TuiChoicePrompt>('tuiChoice') ?? TuiChoicePrompt();

  late final TuiPermissionGate? _gate;

  /// 定义目录监听；`/reload` 与自动重载共用。
  bool _definitionsDirty = false;
  late final DefinitionWatcher _definitionWatcher = DefinitionWatcher(
    roots: _app.get<List<String>>('definitionRoots') ?? const <String>[],
    onInvalidate: _onDefinitionsChanged,
  );

  /// 会话自身没有 `permission/mode` 记录时采用的权限模式（来自配置）。
  ///
  /// 一旦用户在会话里切过模式，持久化的记录优先于它。
  final TuiPermissionMode initialPermissionMode;

  /// 顶栏展示的场景名。
  final String name;

  /// 顶栏展示的模型标签；`/model` 切换后可更新。
  String modelLabel;

  /// 当前模型上下文窗口（token）；0 表示未知（状态栏只显示估算值）。
  /// 由 `/model` 选中项或 models.dev 元数据回填。
  int modelContextLength = 0;

  /// 当前会话消息体量（token）。
  ///
  /// 有一轮真实用量后用**接口返回的 `prompt_tokens`**——它正是下一次请求要发的
  /// 全部内容（含 system prompt、工具定义、工具结果），比拿屏上记录按 chars/4
  /// 猜准得多。首轮之前没有真实数据，才退回估算。
  int get contextTokens {
    final CostTrackerImpl? tracker = _app.get<CostTrackerImpl>('costTracker');
    if (tracker != null && tracker.hasRealUsage) {
      return tracker.lastPromptTokens;
    }
    return estimateMessagesTokens(<LlmMessage>[
      for (final TuiMessage message in transcript.messages)
        LlmMessage(message.role.name, message.text),
    ]);
  }

  /// 上下文用量是估算还是实测（状态栏据此决定加不加 `~`）。
  bool get contextTokensEstimated =>
      !(_app.get<CostTrackerImpl>('costTracker')?.hasRealUsage ?? false);

  /// Agent Loop 单轮最大步数。
  final int maxSteps;

  /// 会话是否先跑规划轮（`todowrite`）再执行；开启后每条新任务会先产出
  /// TODO 计划（屏上 `plan` 消息），执行过程从第一步可见。
  final bool planning;

  /// 启动时是否新建了会话（显式 `--session` / `--continue` 为 false）。
  ///
  /// 仅新会话显示欢迎信息；恢复指定会话时保持安静。
  final bool _newSessionAtStart;

  /// 启动后是否默认进入 Plan Mode（`default_plan_mode` / `--plan`）。
  ///
  /// 会话里已有 `plan/mode` 事件时以事件为准，不覆盖用户上次的选择。
  final bool startInPlanMode;

  /// 退出请求（`/exit`、`/quit`、Ctrl+C）；由宿主接 `shutdownApp`。
  final void Function()? onExit;

  /// `/project open` 请求：宿主接重启/新进程；null 表示当前模式不支持。
  final void Function(String workdir)? onSwitchProject;

  /// 会话装配钩子：会话子上下文与 Session 建好、内置插件提供完毕后回调。
  ///
  /// 宿主可在此往该会话的子上下文里挂自己的插件/服务（如提供 'tasks' 任务中心）。
  /// 缺省 null，不注入时行为与接入前一致。随会话绑定调用一次；切会话时子上下文
  /// 释放，钩子里登记的效应自动撤销。
  void Function(Context sessionCtx, Session session)? configureSession;

  /// `/model [名字]` 钩子：返回给用户的提示文本（null 表示不提示）。
  ///
  /// 缺省 null 时该命令提示先配置提供商（/provider add 或编辑 config.toml）。
  /// 宿主（如 playground）在此切换 LLM 提供商：
  /// 替换根上下文服务后调 [rebind] 让 Agent Loop 用上新提供商。
  Future<String?> Function(String arg)? onModelCommand;

  /// LLM 服务替换钩子（由 `ConatusTuiRuntime.createController` 注入）。
  ///
  /// `/model` 切换模型名时调用；未注入时该命令只提示不可用。
  void Function(FallbackLlm llm)? switchLlm;

  /// models.dev 目录拉取器（测试可注入桩）；缺省从本地缓存拉取。
  ///
  /// `/model` 打开浮层时，当前提供商没有配置模型清单（`[models.*]`）时兜底拉取。
  Future<Map<String, List<ModelsDevModel>>> Function()? modelsDevLoader;

  /// `/undo` 覆盖工作区前的确认钩子（返回 `false` 取消）。
  ///
  /// 缺省走选项浮层；测试 / 无界面运行时注入桩，避免弹窗等不到人。
  Future<bool> Function(String message)? confirmRevert;

  /// `/team`（无参）进入团队视图的宿主回调；由根组件注入切换视图。
  void Function()? onOpenTeamView;

  /// provider 管理浮层（`/provider`，只读展示）。
  late final TuiProviderPrompt providerPrompt = TuiProviderPrompt(
    onChanged: _refresh,
  );

  /// 模型选择浮层（`/model` 打开；搜索过滤，Enter 切换）。
  late final TuiModelPrompt modelPrompt = TuiModelPrompt(onChanged: _refresh);

  /// 权限模式选择浮层（`/permission` 打开；↑↓ 选择，Enter 切换）。
  late final TuiPermissionPrompt permissionPrompt = TuiPermissionPrompt(
    onChanged: _refresh,
  );

  /// 主题选择浮层（`/theme` 打开；↑↓ 选择，Enter 应用）。
  late final ThemePrompt themePrompt = ThemePrompt(onChanged: _refresh);

  /// Plan Mode 面板浮层（`/plan`）。
  late final TuiPlanPrompt planPrompt = TuiPlanPrompt(onChanged: _refresh);

  /// 设置面板（`/settings`；分页列表，选中后跳到对应命令面板）。
  late final SettingsPrompt settingsPrompt = SettingsPrompt(onChanged: _refresh);

  /// 设置面板是否打开。
  bool get settingsOpen => settingsPrompt.open;

  /// 当前工作目录：配置的 `[agent] workdir`，缺省为进程 cwd。
  String get workdir => _app.get<String>('workdir') ?? Directory.current.path;

  /// Agent 选择面板（`/agents` 打开）。
  late final AgentPicker agentPicker = AgentPicker(onChanged: _refresh);

  /// 表单浮层。
  late final TuiFormPrompt formPrompt = TuiFormPrompt(onChanged: _refresh);

  /// 会话重命名浮层（`/rename` 与面板 `r`）。
  late final TuiRenamePrompt renamePrompt = TuiRenamePrompt(
    onChanged: _refresh,
  );

  /// 删除会话前的确认钩子（返回 `false` 取消）。
  ///
  /// 缺省走选项浮层；测试 / 无界面运行时注入桩，避免弹窗等不到人。
  Future<bool> Function(String id)? confirmDelete;

  /// 已报告过读取失败的会话 id：同一次运行只提示一次，避免每次开面板刷屏。
  final Set<String> _failedSessionLoads = <String>{};

  /// 面板读取某会话失败：提示一次，该行按「无历史」展示。
  void _reportSessionLoadError(String id) {
    if (!_failedSessionLoads.add(id)) {
      return;
    }
    transcript.add(
      TuiRole.system,
      '会话 $id 的数据读取失败（JSONL 可能损坏），面板按无历史显示；'
      '原始文件未改动。',
    );
  }

  /// 屏上记录。
  final Transcript transcript = Transcript();

  /// 会话选择面板。
  late final TuiSessionPicker picker;

  /// 会话标签（视图态单活：同一时刻只有一个会话绑定 Agent Loop）。
  final TabManager tabs = TabManager();

  /// 离开当前标签前保存聊天滚动位置（由视图注入）。
  void Function()? onTabLeave;

  /// 切换完成后恢复目标标签的滚动位置（由视图注入）。
  void Function(double offset)? onTabRestore;

  /// 状态变化通知（组件据此 `setState`）。
  void Function()? onChanged;

  String _sessionId;
  Session? _session;
  Context? _sessionCtx;
  AgentLoop? _agent;
  PlanMode? _planMode;
  GoalService? _goal;
  Disposer? _eventSub;

  /// 当前会话的 UI sidecar（滚动 / 输入历史）。
  SessionUiState _uiState = SessionUiState.empty;
  int _historyIndex = -1;
  String _historyDraft = '';
  double? _pendingScroll;

  /// turn 0 基线快照的落盘门闩：`_bind` 起拍、`submit` 与 `/rewind` 等待。
  ///
  /// 非空表示有一轮基线在飞（会话刚绑定）。解除绑定时置 `null`，免得旧门闩
  /// 拖住下一个会话的首轮。
  Future<void>? _checkpointBase;

  /// 最近一次 `/undo` 的撤销点；发新 prompt（提交语义）或 `/redo` 后清空。
  RevertStage? _revertStage;

  /// 撤销 / 重做进行中：拒绝新 prompt 与并发撤销命令，内部的换会话放行。
  ///
  /// 文件恢复 + 分叉 + 切会话是一串 await；期间若让一轮对话跑起来，工作区会
  /// 在被回滚的同时被工具改写，切会话也会被 busy 拒绝，留下半套状态。
  bool _revertInFlight = false;

  /// 待回填到输入框的文本（`/undo` 回填被撤回的 prompt）；根组件取走即清空。
  String? _prefill;

  /// `/diff` 视图是否打开。
  bool _diffOpen = false;

  /// `/diff` 当前比较范围。
  DiffScope _diffScope = DiffScope.working;

  /// `/diff` 最近一次加载的文件差异。
  List<FileDiff> _diffFiles = const <FileDiff>[];

  /// `/diff` 数据源降级说明（git 不可用 / 检查点缺失）；正常为 `null`。
  String? _diffNotice;

  /// `/diff` 加载代次：切换范围与关闭时递增，丢弃迟到的结果。
  int _diffEpoch = 0;

  /// `/diff` 的工作区根；缺省当前目录（测试指向临时仓库）。
  String? diffWorkdir;

  /// 在飞轮次的取消句柄（Esc / 打断）；null = 无在飞轮次。
  AgentCancel? _cancel;

  /// 当前轮是否已被用户打断；打断后丢弃迟到的流式增量。
  ///
  /// `streamChatResult` 被取消后底层 HTTP 流不会立刻停止，仍可能吐几个
  /// reasoning / text 增量；若照单全收，屏上会在「已打断这一轮」之后又出现
  /// 一段思考，看起来像自动发起了新请求。
  bool _turnInterrupted = false;

  /// 团队订阅（随会话绑定/解绑）。
  TeamSubscription? _teamSub;

  /// 当前权限模式（随绑定的会话变化）。
  TuiPermissionMode _permissionMode = TuiPermissionMode.askWhenNeeded;

  /// 是否有在途轮次。
  bool busy = false;

  DateTime? _turnStartedAt;
  DateTime? _turnFinishedAt;
  Duration? _lastTurnDuration;
  bool _lastTurnOk = true;
  bool _lastTurnInterrupted = false;
  bool _lastTurnBudget = false;

  /// 当前轮已运行时长；空闲时为 null。
  Duration? get turnElapsed => _turnStartedAt == null
      ? null
      : DateTime.now().difference(_turnStartedAt!);

  /// 最近一轮的完成时长；只在完成后 15 秒内返回（用于状态栏「✓ 完成」）。
  Duration? get recentTurnDuration {
    final DateTime? finished = _turnFinishedAt;
    if (finished == null) return null;
    if (DateTime.now().difference(finished) > const Duration(seconds: 15)) {
      return null;
    }
    return _lastTurnDuration;
  }

  void _beginTurn() {
    _turnStartedAt = DateTime.now();
    _turnFinishedAt = null;
    _lastTurnDuration = null;
  }

  /// 最近一轮的状态标签；完成后 15 秒内返回。
  String? get recentTurnStatus {
    if (recentTurnDuration == null) return null;
    if (_lastTurnInterrupted) return '⏹ 已中断';
    if (_lastTurnBudget) return '⚠ 预算收口';
    return _lastTurnOk ? '✓ 完成' : '✗ 失败';
  }

  void _endTurn({
    required bool ok,
    bool interrupted = false,
    bool budget = false,
  }) {
    final DateTime now = DateTime.now();
    final DateTime? started = _turnStartedAt;
    _turnStartedAt = null;
    _turnFinishedAt = now;
    _lastTurnDuration = started == null ? null : now.difference(started);
    _lastTurnOk = ok;
    _lastTurnInterrupted = interrupted;
    _lastTurnBudget = budget;
  }

  /// 排队中的用户输入（busy 时入队，收口后依次投递；上限 [kMessageQueueCap]）。
  final List<(String, List<TuiAttachment>)> _queue =
      <(String, List<TuiAttachment>)>[];

  /// 排队消息条数。
  int get queuedCount => _queue.length;

  /// 会话是否已绑定就绪。
  bool ready = false;

  /// turn 0 基线快照已落盘。
  ///
  /// [ready] 只保证会话历史可读；基线是后台起拍的（大工作区可达数十秒）。
  /// 内部在 [submit] 与 `/rewind` 前自动等待，此 getter 供测试与外部在
  /// 「就绪但基线未落盘」的窗口里显式同步。
  Future<void> get checkpointSettled => _checkpointBase ?? Future<void>.value();

  /// 当前会话 id。
  String get sessionId => _sessionId;

  /// 当前会话；未绑定为 `null`（测试与外部只读检查用）。
  Session? get session => _session;

  /// 当前会话 Agent ID。
  String get agentId => _agentId;

  /// Plan Mode 是否激活（`/plan` 或 `plan` Agent）。
  bool get planModeActive => _planMode?.state == PlanModeState.active;

  /// 当前 Agent 定义；注册表未装配或未命中时为 `null`。
  AgentDefinition? get agentDefinition => _agentRegistry?.byId(_agentId);

  AgentRegistry? get _agentRegistry => _app.get<AgentRegistry>('agentRegistry');

  CommandRegistry? get _commandRegistry =>
      _app.get<CommandRegistry>('commandRegistry');

  /// `/diff` 视图是否打开。
  bool get diffOpen => _diffOpen;

  /// `/diff` 当前比较范围。
  DiffScope get diffScope => _diffScope;

  /// `/diff` 当前文件差异。
  List<FileDiff> get diffFiles => _diffFiles;

  /// `/diff` 数据源降级说明；正常为 `null`。
  String? get diffNotice => _diffNotice;

  /// 当前权限模式。
  @override
  TuiPermissionMode get permissionMode => _permissionMode;

  /// 状态栏展示的权限模式名。
  String get permissionLabel {
    final String label = _permissionMode.label;
    return planModeActive ? '$label plan' : label;
  }

  /// 团队状态快照（未装配团队或未绑定时为空）。
  TeamSnapshot get teamSnapshot => _teamSub?.snapshot ?? const TeamSnapshot();

  /// 追加一条系统提示并重绘（权限规则保存失败等降级路径用）。
  void showSystemNotice(String text) {
    transcript.add(TuiRole.system, text);
    _refresh();
  }

  /// 把「总是允许」规则写入项目 `permissions.json` 并更新根作用域。
  ///
  /// [resources] 是本次批准的具体资源，用于阻止 allow 覆盖已有 deny。
  /// 拒绝/失败时保留会话内临时放行（调用方已加白名单），只把原因上屏。
  Future<void> rememberPermissionRules(
    List<PermissionRule> rules,
    List<String> resources,
  ) async {
    final PermissionWiring? wiring = _app.get<PermissionWiring>(
      'permissionWiring',
    );
    if (wiring == null) return;
    final String? warning = await wiring.remember(rules, resources);
    if (warning != null) showSystemNotice('权限规则未保存：$warning');
  }

  /// 切换权限模式：持久化到当前会话、更新根权限作用域阈值并提示。
  ///
  /// 会话未绑定时拒绝：此时既无法持久化、模式也会在绑定后被恢复逻辑覆盖，
  /// 静默生效只会让界面提示与实际状态不符。
  @override
  void applyPermissionMode(TuiPermissionMode mode) {
    final Session? session = _session;
    if (session == null) {
      transcript.add(TuiRole.system, '会话尚未就绪，权限模式未切换。');
      _refresh();
      return;
    }
    if (mode == _permissionMode) {
      return;
    }
    _permissionMode = mode;
    session.append(
      kPermissionModeEvent,
      data: <String, Object?>{'mode': mode.name},
    );
    _syncPermissionMode();
    transcript.add(
      TuiRole.system,
      '权限模式已切换为「${mode.label}」：${mode.description}',
    );
    _refresh();
  }

  /// 按当前模式更新根权限作用域的兜底阈值（幂等）。
  ///
  /// 权限中间件只在根上下文挂一次（见 `instrumentPermission`），这里不需要
  /// 重挂任何中间件：换会话 / 换模式只改槽位里的 `askThreshold`。
  void _syncPermissionMode() {
    final ToolRisk? threshold = _permissionMode.threshold;
    final PermissionWiring? wiring = _app.get<PermissionWiring>(
      'permissionWiring',
    );
    if (wiring != null) {
      wiring.applyMode(askThreshold: threshold, agentId: _agentId);
      return;
    }
    final PermissionScopeSlot? slot = _app.get<PermissionScopeSlot>(
      kPermissionScopeService,
    );
    slot?.set(
      PermissionScope(
        rules: slot.current.rules,
        askThreshold: threshold,
        agentId: _agentId,
      ),
    );
  }

  /// 把当前 Agent 的系统提示注入 system prompt（重复调用先撤销上一段）。
  ///
  /// 内置 `build` 的人设与全局 persona 重复，不注入；自定义同名 Agent
  /// （`sourcePath` 指向文件）照常注入。
  void _applyAgentPrompt() {
    _agentPromptDisposer?.call();
    _agentPromptDisposer = null;
    final AgentDefinition? def = agentDefinition;
    final String system = def?.system.trim() ?? '';
    if (system.isEmpty || def?.sourcePath == 'builtin:build') {
      return;
    }
    final SystemPrompt? prompt = _app.get<SystemPrompt>('systemPrompt');
    _agentPromptDisposer = prompt?.section(
      PromptSection(
        name: 'agent-${identityHashCode(this)}',
        order: -10,
        text: () => system,
      ),
    );
  }

  /// 绑定初始会话；未配置 provider 时自动打开引导面板。
  ///
  /// 未指定会话 id（构造时 `initialSession` 为 `null`）时，先经会话仓库新建
  /// 一个 `session_<uuid>` 会话再绑定，不会恢复历史会话。
  Future<void> start() async {
    _agentId = _startupAgentId();
    _modelBaseline = _currentModelChoice();
    await _applyStartupAgentModel();
    if (_sessionId.isEmpty) {
      _sessionId = _sessions.create().id;
    }
    await _bindStartup(_sessionId);
    _firstBind = false;
    if (_newSessionAtStart) _addStartupBanner();
    _applyStartInPlanMode();
    _persistAgentSelection();
    _syncTabState();
    _restoreActiveScroll();
    _addKeybindWarnings();
    _addDiscoveryWarnings();
    _refresh();
    // 回填当前模型的上下文窗口（来自 models.dev 档案，未就绪则稍后补）。
    seedModelContextLength();
    _watchModelProfiles();
    _definitionWatcher.start();
    if (_app.get<bool>('providerSetupNeeded') ?? false) {
      final ProviderRegistry? registry = _app.providers;
      if (registry != null) {
        providerPrompt.show(providerItems(registry));
      }
    }
  }

  /// 绑定启动会话；读取失败（JSONL 损坏）时换一个新会话并提示。
  Future<void> _bindStartup(String id) async {
    try {
      await _bind(id);
    } catch (error) {
      await _bindFallbackSession(id, error);
    }
  }

  /// 打开备用会话；失败只提示、不向上抛（启动与恢复都必须保持可用）。
  Future<bool> _bindFallbackSession(String failedId, Object error) async {
    try {
      _sessionId = _sessions.create().id;
      await _bind(_sessionId);
      transcript.add(
        TuiRole.system,
        '会话 $failedId 读取失败（数据可能损坏），已改开新会话 $_sessionId：$error',
      );
      return true;
    } catch (fallbackError) {
      transcript.add(
        TuiRole.system,
        '会话 $failedId 读取失败，备用会话也未能打开：$fallbackError',
      );
      return false;
    }
  }

  /// 把当前绑定的会话同步到标签：已存在则更新标题并激活，否则新开一个。
  void _syncTabState() {
    final String id = _sessionId;
    if (id.isEmpty || !ready) return;
    final String title = _tabTitle(_session);
    final int existing = tabs.indexOf(id);
    if (existing >= 0) {
      tabs.retitle(id, title);
      tabs.activate(existing);
      return;
    }
    tabs.open(id, title: title);
  }

  /// 标签标题：优先会话标题，旧会话回退首条用户消息（与面板一致）。
  String _tabTitle(Session? session) {
    if (session == null) return '';
    return session.title ?? deriveSessionTitle(session.events) ?? '';
  }

  /// 把键位配置的告警（未知动作 / 非法键位 / 冲突）上屏。
  void _addKeybindWarnings() {
    for (final String warning in keymap.warnings) {
      transcript.add(TuiRole.system, warning);
    }
  }

  /// 启动时把 Agent / 命令发现告警上屏（来源文件与原因都在告警文本里）。
  ///
  /// 只展示前 5 条；其余提示去 `/doctor` 看，避免坏目录一次刷屏。
  void _addDiscoveryWarnings() {
    final List<String> warnings = <String>[
      ...?_agentRegistry?.warnings,
      ...?_commandRegistry?.warnings,
      ...?_app.get<AgentProfileResolver>('agentProfiles')?.warnings,
      ...?_app.get<List<String>>('configWarnings'),
    ];
    for (final String warning in warnings.take(5)) {
      transcript.add(TuiRole.system, warning);
    }
    if (warnings.length > 5) {
      transcript.add(
        TuiRole.system,
        '还有 ${warnings.length - 5} 条 Agent / 命令发现告警，见 /doctor。',
      );
    }
  }

  /// 解析启动 Agent：显式配置优先；未知 / 仅子 Agent 回退注册表默认值。
  String _startupAgentId() {
    final AgentRegistry? registry = _agentRegistry;
    final String requested = initialAgentId?.trim() ?? '';
    if (registry == null) {
      return requested.isEmpty ? 'build' : requested;
    }
    if (requested.isNotEmpty) {
      final AgentDefinition? explicit = registry.byId(requested);
      if (explicit != null && explicit.mode != AgentMode.subagent) {
        return explicit.id;
      }
    }
    return registry.defaultAgent.id;
  }

  /// 新会话的 Agent：`[agent] default_agent`（注册表已处理未知 / subagent 回退）。
  String _defaultAgentId() => _agentRegistry?.defaultAgent.id ?? 'build';

  /// 目录变更：空闲时立即重载，忙时排队到本轮结束。
  void _onDefinitionsChanged() {
    if (busy || _revertInFlight) {
      _definitionsDirty = true;
      showSystemNotice('Agent / 命令定义已变更，当前操作结束后自动重载。');
      return;
    }
    unawaited(reloadDefinitions());
  }

  /// 重新发现 Agent / 命令定义，并按需重绑当前 Agent。
  Future<void> reloadDefinitions({bool announce = true}) async {
    final AgentRegistry? agents = _agentRegistry;
    final CommandRegistry? commands = _commandRegistry;
    if (agents == null || commands == null) {
      showSystemNotice('Agent / 命令注册表未装配，无法重载定义。');
      return;
    }
    if (busy || _revertInFlight) {
      _definitionsDirty = true;
      if (announce) showSystemNotice('有操作进行中，结束后自动重载定义。');
      return;
    }
    await agents.reload();
    await commands.reload();
    _definitionsDirty = false;
    if (ready) {
      final AgentDefinition? current = agents.byId(_agentId);
      final bool removed =
          current == null || current.mode == AgentMode.subagent;
      final String target = removed ? agents.defaultAgent.id : current.id;
      await _activateAgent(target, announce: removed, syncPlanMode: false);
    }
    if (announce) showSystemNotice('已重载 Agent / 命令定义。');
    _refresh();
  }

  /// 会话记录的 Agent；无记录、未知或仅子 Agent 时用 [fallback]。
  String _sessionAgentId(Session session, String fallback) {
    final String? recorded = restoreAgentId(session);
    if (recorded == null) return fallback;
    final AgentDefinition? def = _agentRegistry?.byId(recorded);
    if (def == null || def.mode == AgentMode.subagent) return fallback;
    return def.id;
  }

  /// 首次绑定 / 显式切换后把当前 Agent 写入会话；重复选择不追加。
  void _persistAgentSelection() {
    final Session? session = _session;
    if (session == null) return;
    persistAgentSelection(session, _agentId);
  }

  /// 当前 LLM 链 + 标签；无链时 entries 为空。
  _ModelChoice _currentModelChoice() {
    final LlmChain? chain = _app.get<LlmChainSlot>('llmChainSlot')?.current;
    return _ModelChoice(
      entries: List<String>.of(chain?.entries ?? const <String>[]),
      label: modelLabel,
    );
  }

  /// 两组模型候选是否完全一致（含展示标签）。
  bool _sameModelChoice(_ModelChoice left, _ModelChoice right) {
    if (left.label != right.label) return false;
    if (left.entries.length != right.entries.length) return false;
    for (int index = 0; index < left.entries.length; index++) {
      if (left.entries[index] != right.entries[index]) return false;
    }
    return true;
  }

  /// 把当前链记为基线（用户 `/model`、`/provider` 显式切换后调用）。
  void _rememberModelBaseline() => _modelBaseline = _currentModelChoice();

  /// 启动 Agent 自带模型时先换链，再绑定会话。
  Future<void> _applyStartupAgentModel() async {
    final String? spec = _agentRegistry?.byId(_agentId)?.model;
    if (spec == null) return;
    final String? warning = await _applyModelSpec(spec, rebindNow: false);
    if (warning != null) {
      transcript.add(TuiRole.system, '启动 Agent 的模型不可用：$warning，沿用当前模型。');
    }
  }

  /// 切会话后按目标会话的 Agent 恢复模型（无 `model:` 时回到基线）。
  ///
  /// AgentLoop 在 `_bind` 时已经捕获了旧的 `LlmProvider`，只换链槽位不会
  /// 影响它；因此这里必须带着重绑一起切换（否则标签看起来换了模型，真实
  /// 请求仍走旧模型）。
  Future<void> _restoreBoundAgentModel() async {
    final String? spec = agentDefinition?.model;
    if (spec != null && spec.trim().isNotEmpty) {
      final String? warning = await _applyModelSpec(spec);
      if (warning != null) {
        showSystemNotice('Agent $_agentId 的模型不可用：$warning，沿用当前模型。');
      }
      return;
    }
    final _ModelChoice? baseline = _modelBaseline;
    if (baseline == null || _sameModelChoice(_currentModelChoice(), baseline)) {
      return;
    }
    if (_restoreBaselineModel()) await rebind();
  }

  /// 释放当前会话绑定（幂等）。
  void dispose() {
    _definitionWatcher.stop();
    _unbind();
    // 提示订阅跨会话存活（换会话不该丢「正在重试」的可见性），只在控制器
    // 真正销毁时取消。
    unawaited(_noticeSubscription?.cancel());
    _noticeSubscription = null;
    unawaited(_modelProfileSub?.cancel());
    _modelProfileSub = null;
    unawaited(_subagentSub?.cancel());
    _subagentSub = null;
  }

  /// 重新绑定当前会话：替换根上下文服务（如 `'llm'`）后调用，让 Agent Loop
  /// 用新服务重建；屏上记录按会话事件重建，历史不丢。
  ///
  /// 有在途轮次时不动（避免打断），返回是否确实重绑。
  Future<bool> rebind() async {
    if (!ready || busy) return false;
    final String id = _sessionId;
    _unbind();
    await _bind(id);
    _refresh();
    return true;
  }

  /// 以 [agentId] 重绑当前会话（自定义命令的临时 Agent 覆盖用）。
  ///
  /// 覆盖只作用于这次重绑；会话事件不动，回合结束的还原路径照常生效。
  Future<bool> _rebindAs(String agentId) async {
    _bindAgentOverride = agentId;
    try {
      return await rebind();
    } finally {
      _bindAgentOverride = null;
    }
  }

  /// 处理一行输入：斜杠命令本地处理，其余进对话链路。
  ///
  /// 非斜杠行先经 [expandAtRefs] 展开 `@<路径>` 文件引用（fs 服务不可用时
  /// 原样发送），再连同 [attachments] 提交给 Agent Loop。
  Future<void> handleLine(
    String raw, {
    List<TuiAttachment> attachments = const <TuiAttachment>[],
  }) async {
    final String line = raw.trim();
    if (line.isEmpty) {
      return;
    }
    _recordInput(line);
    if (line.startsWith('!')) {
      // `!命令` 直接执行 shell，不经模型（busy 时拒绝）。
      await _runShellBang(line);
      return;
    }
    if (line.startsWith('/')) {
      final String rest = line.replaceFirst(RegExp('^/+'), '');
      final int space = rest.indexOf(' ');
      final String command = space < 0 ? rest : rest.substring(0, space);
      final String arg = space < 0 ? '' : rest.substring(space + 1).trim();
      await _handleCommand(command, arg);
      return;
    }
    await submit(
      await expandAtRefs(line, fs: _app.get<FileSystem>('fs')),
      attachments: attachments,
    );
  }

  /// `/undo [N]`：按轮撤销工作区文件与对话，留下可 `/redo` 的撤销点。
  Future<void> undo(int steps) => _runUndo(steps);

  /// `/redo`：回到最近一次 `/undo` 之前（恢复文件并切回原会话）。
  Future<void> redo() => _runRedo();

  /// `/diff`：加载 [scope] 范围内的差异并打开只读视图。
  ///
  /// 空结果也打开视图（由视图给出「没有可显示的差异」），避免看起来像命令
  /// 没反应；读取失败只进 [diffNotice]，不打断当前会话。
  Future<void> openDiff(DiffScope scope) async {
    _diffScope = scope;
    await _loadDiff();
    _diffOpen = true;
    _refresh();
  }

  /// 视图内 `d` 切换比较范围：先同步范围，再异步重载（[diffOpen] 保持不变）。
  void setDiffScope(DiffScope scope) {
    if (!_diffOpen || scope == _diffScope) {
      return;
    }
    _diffScope = scope;
    unawaited(_loadDiff().then((_) => _refresh()));
  }

  /// 切换 TUI 主题并通知界面重绘；未知名字由 [NavaTheme] 回落 `default`。
  void setTheme(String name) {
    NavaTheme.use(name);
    _refresh();
  }

  /// 关闭 `/diff` 视图，丢弃当前数据与降级说明。
  void closeDiff() {
    _diffOpen = false;
    _diffEpoch++;
    _diffFiles = const <FileDiff>[];
    _diffNotice = null;
    _refresh();
  }

  /// 加载差异；迟到的结果按 [_diffEpoch] 丢弃。
  Future<void> _loadDiff() async {
    final int epoch = ++_diffEpoch;
    final CheckpointManager? checkpoint = _app.get<CheckpointManager>(
      'checkpointManager',
    );
    if (checkpoint == null) {
      _applyDiff(epoch, const <FileDiff>[], '未装配检查点，无法读取差异。');
      return;
    }
    final DiffSource source = DiffSource(
      workdir:
          diffWorkdir ?? _app.get<String>('workdir') ?? Directory.current.path,
      checkpoint: checkpoint,
      sessionId: _sessionId,
    );
    List<FileDiff> diffs = const <FileDiff>[];
    String? notice;
    try {
      diffs = await source.load(_diffScope);
      notice = source.notice;
    } catch (error) {
      notice = '读取差异失败：$error';
    }
    _applyDiff(epoch, diffs, notice);
  }

  void _applyDiff(int epoch, List<FileDiff> diffs, String? notice) {
    if (epoch != _diffEpoch) {
      return;
    }
    _diffFiles = diffs;
    _diffNotice = notice;
  }

  /// `/diff [working|turn]`：参数非法时给用法提示且不打开视图。
  Future<void> _handleDiff(String arg) async {
    final DiffScope? scope = _parseDiffScope(arg);
    if (scope == null) {
      transcript.add(TuiRole.system, kDiffUsage);
      return;
    }
    await openDiff(scope);
  }

  DiffScope? _parseDiffScope(String arg) {
    if (arg.isEmpty || arg == 'working') {
      return DiffScope.working;
    }
    return arg == 'turn' ? DiffScope.turn : null;
  }

  /// 回填输入框：由根组件在下一次重绘时取走（`/undo` 回填被撤回的 prompt）。
  void prefillInput(String text) {
    _prefill = text;
    _refresh();
  }

  /// 取走待回填文本；没有待回填内容时返回 `null`（只返回一次）。
  String? takePrefillInput() {
    final String? text = _prefill;
    _prefill = null;
    return text;
  }

  /// 上一条 `!` 命令（`!!` 重跑用）。
  String? _lastBangCommand;

  /// `!<命令>`：直接执行 shell 命令（不经模型）；`!!` 重跑上一条。
  Future<void> _runShellBang(String line) async {
    if (busy) {
      transcript.add(TuiRole.system, '有在途轮次，请稍候再试。');
      _refresh();
      return;
    }
    final String command = _bangCommand(line);
    if (command.isEmpty) {
      _refresh();
      return;
    }
    _lastBangCommand = command;
    await _runShellForUser(command);
    // Transcript.add 不会通知重绘；执行完必须显式刷新，否则结果要等下一次
    // 无关事件（按键等）才上屏，看起来像命令很慢。
    _refresh();
  }

  /// 解析 `!` 行：返回要执行的命令（空串 = 已提示用法，不执行）。
  String _bangCommand(String line) {
    final String raw = line.substring(1).trim();
    if (raw.isEmpty) {
      transcript.add(TuiRole.system, '用法：!<命令> 直接执行（如 !git status）；!! 重跑上一条。');
      return '';
    }
    if (raw != '!') return raw;
    final String? last = _lastBangCommand;
    if (last == null) {
      transcript.add(TuiRole.system, '没有可重跑的上一条命令。');
      return '';
    }
    return last;
  }

  /// 执行用户直发的 shell 命令并上屏：走 `'shellInteractive'` 交互缝（缺省本地
  /// 直执，对齐 OpenCode）；模型工具仍走 `'shell'` 沙箱缝，不受影响。
  Future<void> _runShellForUser(String command) async {
    final ShellExecutor? shell =
        _app.get<ShellExecutor>('shellInteractive') ??
        _app.get<ShellExecutor>('shell');
    if (shell == null) {
      transcript.add(TuiRole.system, 'shell 不可用。');
      return;
    }
    transcript.add(TuiRole.system, '\$ $command');
    _refresh(); // 命令回显先上屏，长命令执行期间也有反馈。
    final ShellRunResult result;
    try {
      result = await shell.run(
        shell.resolve(
          ShellExecRequest(command: command, timeoutMs: kShellBangTimeoutMs),
        ),
      );
    } catch (error) {
      transcript.add(TuiRole.system, '命令执行失败：$error');
      return;
    }
    transcript.add(TuiRole.system, _bangOutput(result));
  }

  /// 把执行结果映射为展示文本。
  String _bangOutput(ShellRunResult result) {
    if (result.timedOut) return '命令超时（${kShellBangTimeoutMs ~/ 1000}s）。';
    final int? code = result.exitCode;
    if (code == 0) {
      final String out = result.stdout.text;
      return out.isEmpty ? '（无输出）' : out;
    }
    final String body = _joinedOutput(result.stdout.text, result.stderr.text);
    // 127 是 shell「命令未找到」的约定退出码：错误行原样直出，不加
    // 「命令失败（exit 127）」包装，观感与终端直出一致。
    if (code == 127 && body.isNotEmpty) return body;
    return '命令失败（exit $code）：${body.isEmpty ? '（无输出）' : body}';
  }

  /// 打断在飞轮次（Esc / barge-in）：立即提示，盘上记录保留；排队消息一并清空。
  ///
  /// 空闲时（无在飞轮次）也给出提示，打断按键始终有反馈。
  void interrupt() {
    final AgentCancel? cancel = _cancel;
    if (cancel == null) {
      transcript.add(TuiRole.system, '当前没有进行中的对话。');
      _refresh();
      return;
    }
    _turnInterrupted = true;
    cancel.cancel();
    // 前台子 Agent 命令用同一个 _cancel 门面；闭包里同时收掉真正的
    // SpawnAgentTool（子 Agent 不走主轮次的取消竞速）。
    _foregroundInterrupt?.call();
    // 普通聊天轮次里的子 Agent 也一并收掉，否则它在后台继续烧 token。
    final Tool? spawn = _app.tools.get('task');
    if (_foregroundInterrupt == null && spawn is SpawnAgentTool) {
      spawn.interrupt();
    }
    final int queued = _queue.length;
    if (queued > 0) {
      _queue.clear();
      transcript.add(TuiRole.system, '正在打断…已清空 $queued 条排队消息。');
    } else {
      transcript.add(TuiRole.system, '正在打断…');
    }
    _refresh();
  }

  /// 提交一轮对话；[attachments] 为粘贴/拖放登记的附件（图片 + 文本文件）。
  Future<void> submit(
    String text, {
    List<TuiAttachment> attachments = const <TuiAttachment>[],
  }) async {
    if (_revertInFlight) {
      // 撤销/重做正在改工作区与切会话：此时起一轮会让回滚与工具写入交错。
      transcript.add(TuiRole.system, '正在撤销/重做，请稍候。');
      _refresh();
      return;
    }
    if (busy) {
      // busy 时排队追问（上限 [kMessageQueueCap]）；未绑定会话不排队。
      if (_agent == null) {
        transcript.add(TuiRole.system, '正在回复，请稍候（Esc 可打断）。');
        _refresh();
        return;
      }
      if (_queue.length >= kMessageQueueCap) {
        transcript.add(TuiRole.system, '排队已满（$kMessageQueueCap 条），请稍后再试。');
        _refresh();
        return;
      }
      _queue.add((text, attachments));
      transcript.add(
        TuiRole.system,
        '已排队（第 ${_queue.length} 条），当前轮结束后依次处理（Esc 打断时清空）。',
      );
      _refresh();
      return;
    }
    final AgentLoop? agent = _agent;
    if (agent == null) {
      transcript.add(TuiRole.system, '会话尚未就绪，请稍候。');
      _refresh();
      return;
    }
    List<LlmImage> images = const <LlmImage>[];
    String messageText = text;
    if (attachments.isNotEmpty) {
      final AttachmentMaterialization? payload = await _materializeAttachments(
        attachments,
      );
      if (payload == null) return;
      images = payload.images;
      messageText = payload.inlineText + text;
    }
    final AgentCancel cancel = AgentCancel();
    _cancel = cancel;
    _turnInterrupted = false;
    // 新 prompt 即提交：撤销点与待回填内容作废（/redo 不再可用）。
    _revertStage = null;
    _prefill = null;
    _beginTurn();
    busy = true;
    _refresh();
    // 等 turn 0 基线落盘再开跑：快照边写边读工作区，飞行中被工具改动会
    // 拍出「半旧半新」的 base，之后 /rewind 回到从未存在过的混合状态。
    // 界面此时已就绪，用户能看到历史并排队，这里只是把首轮延后。
    await _checkpointBase;
    bool turnOk = true;
    bool interrupted = false;
    bool budgetExhausted = false;
    String reply = '';
    // 用户每提交一次就是新的一轮：不能靠空闲时间推断轮边界，否则连续追问
    // 会把上一轮墙钟累计进来，正常对话中途误报预算并返回空回复。
    final LlmProvider? budgetedLlm = _app.get<LlmProvider>('llm');
    if (budgetedLlm is BudgetedLlmProvider) budgetedLlm.beginTurn();
    try {
      final AgentTurn turn = await agent.run(
        messageText,
        cancel: cancel,
        images: images,
      );
      reply = turn.reply;
      budgetExhausted = reply == kBudgetExhaustedReply;
      if (budgetExhausted) {
        turnOk = false;
        transcript.add(
          TuiRole.system,
          '本轮预算已达上限（累计 token 或墙钟），已收口；'
          '可调 [budget] max_turn_tokens / max_turn_seconds。',
        );
      }
      if (turn.emptyReply) {
        turnOk = false;
        transcript.add(TuiRole.system, '模型返回了空回复（输出可能被截断），请重试或换模型。');
      }
    } on AgentCancelled {
      turnOk = false;
      interrupted = true;
      transcript.add(TuiRole.system, '已打断这一轮。');
    } on LlmException catch (error) {
      turnOk = false;
      transcript.add(TuiRole.system, '模型调用失败：${error.message}');
    } catch (error) {
      turnOk = false;
      transcript.add(TuiRole.system, '出错：$error');
    } finally {
      _cancel = null;
      // 同步收尾先行：轮询 busy 的调用方（如 cron 交付）在置闲后即可看到
      // 运行记录已是终态。
      _settleCronRuns(ok: turnOk, reply: reply);
      busy = false;
      _endTurn(ok: turnOk, interrupted: interrupted, budget: budgetExhausted);
      await _afterTurn();
      _refresh();
    }
  }

  /// 附件物化：图片转 [LlmImage]、文本文件转 `<file>` 块；失败提示并返回 null。
  Future<AttachmentMaterialization?> _materializeAttachments(
    List<TuiAttachment> attachments,
  ) async {
    try {
      return await materializeAttachments(attachments);
    } catch (error) {
      transcript.add(TuiRole.system, '附件读取失败：$error');
      _refresh();
      return null;
    }
  }

  /// 打开 / 关闭 / 移动会话面板。
  Future<void> openPicker() => picker.show(_sessionId);
  void closePicker() => picker.close();
  void movePicker(int delta) => picker.move(delta);

  /// `/rename [标题]`：有参直接改当前会话；无参打开输入框（预填已有标题）。
  Future<void> _handleRename(String arg) async {
    if (arg.isNotEmpty) {
      await renameSession(_sessionId, arg);
      return;
    }
    renamePrompt.show(_sessionId, _session?.title);
  }

  /// 重命名会话：追加标题事件并落盘；空标题 / 未知 id / IO 失败只提示。
  Future<bool> renameSession(String id, String title) async {
    if (title.trim().isEmpty) {
      showSystemNotice('会话标题不能为空。');
      return false;
    }
    try {
      final Session? opened = _sessions.get(id);
      final bool known =
          opened != null || (await _sessions.persistedIds()).contains(id);
      if (!known) {
        showSystemNotice('会话 $id 不存在。');
        return false;
      }
      final Session session = opened ?? await _sessions.open(id);
      session.rename(title);
      await _sessions.flush();
      tabs.retitle(id, session.title ?? '');
      transcript.add(TuiRole.system, '已将会话 $id 重命名为「${session.title}」。');
      // 面板里的行是不可变快照：改名后按原选中项重读，别跳到当前会话。
      if (picker.open) {
        await picker.show(_sessionId, selectedId: id);
      }
      _refresh();
      return true;
    } on ArgumentError {
      showSystemNotice('会话标题不能为空。');
      return false;
    } catch (error) {
      showSystemNotice('重命名会话 $id 失败：$error');
      return false;
    }
  }

  /// 提交重命名输入框；未打开或标题为空白时保持打开并返回 `false`。
  Future<bool> commitRename() async {
    final String? id = renamePrompt.targetId;
    if (id == null) {
      return false;
    }
    final String text = renamePrompt.text;
    if (text.trim().isEmpty) {
      showSystemNotice('会话标题不能为空。');
      return false;
    }
    renamePrompt.close();
    return renameSession(id, text);
  }

  /// 面板 `r`：给选中会话打开重命名输入框（预填已有标题）。
  Future<void> openRenameForSelected() async {
    final String? id = picker.selectedId();
    if (id == null) {
      return;
    }
    final Session session = _sessions.get(id) ?? await _sessions.open(id);
    renamePrompt.show(id, session.title);
  }

  /// 面板 `d`：当前会话直接拒绝（不弹确认），其余二次确认后删除。
  Future<void> deleteSelectedSession() async {
    final String? id = picker.selectedId();
    if (id == null) {
      return;
    }
    if (id == _sessionId) {
      showSystemNotice('不能删除当前会话；先切换到别的会话再删。');
      return;
    }
    if (!await _confirmDelete(id)) {
      return;
    }
    await deleteSession(id);
  }

  Future<bool> _confirmDelete(String id) async {
    final Future<bool> Function(String id)? hook = confirmDelete;
    if (hook != null) {
      return hook(id);
    }
    final String summary = await _deleteSummary(id);
    final String? answer = await choice.ask(
      TuiChoiceRequest(
        title: '删除会话 $id？\n$summary',
        choices: const <TuiChoice>[
          TuiChoice(id: 'delete', label: '删除'),
          TuiChoice(id: 'cancel', label: '取消', current: true),
        ],
      ),
    );
    return answer == 'delete';
  }

  /// 删除确认的清理范围：JSONL 大小、检查点数、故事线、导出文件。
  Future<String> _deleteSummary(String id) async {
    final List<String> parts = <String>[];
    final SessionPersistence? persistence = _app.get<SessionPersistence>(
      'sessionPersistence',
    );
    if (persistence is JsonlSessionPersistence) {
      final File file = File(
        '${persistence.dir}${Platform.pathSeparator}$id.jsonl',
      );
      if (file.existsSync()) {
        parts.add('会话数据 ${_fileSizeLabel(file.lengthSync())}');
      }
    }
    final CheckpointManager? checkpoint = _app.get<CheckpointManager>(
      'checkpointManager',
    );
    final int checkpoints = checkpoint?.listFor(id).length ?? 0;
    if (checkpoints > 0) parts.add('检查点 $checkpoints 个');
    final SessionLog? log = _app.get<SessionLog>('sessionLog');
    final String? storyDir = _app.get<String>('storyLogDir');
    if (log != null) {
      try {
        if ((await log.list()).contains(id)) parts.add('故事线日志');
      } catch (_) {
        // 日志不可读不影响删除确认：清理时还会再报一次。
      }
    } else if (storyDir != null &&
        File('$storyDir${Platform.pathSeparator}$id.jsonl').existsSync()) {
      parts.add('故事线日志');
    }
    final String export = _exportFileOf(id);
    if (File(export).existsSync()) parts.add('导出文件保留（$export）');
    return parts.isEmpty ? '没有可清理的附属文件。' : '将清理：${parts.join('；')}。';
  }

  /// 会话的缺省导出路径（与会话导出器 / `[agent] project_dir` 对齐）。
  String _exportFileOf(String id) {
    final String bare = id.startsWith('session_')
        ? id.substring('session_'.length)
        : id;
    return '${_projectDataDir()}'
        '${Platform.pathSeparator}exports${Platform.pathSeparator}nava-$bare.md';
  }

  String _fileSizeLabel(int bytes) =>
      bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB';

  /// 删除会话：拒绝当前会话；清 JSONL、检查点与故事线日志（不动导出文件）。
  ///
  /// 先 flush 在途写入（排队中的标题事件否则可能在删除后重建文件）；每一步
  /// 独立捕获失败，最后一次性报告，避免「删了一半却没有任何提示」。
  Future<bool> deleteSession(String id) async {
    if (id == _sessionId) {
      showSystemNotice('不能删除当前会话；先切换到别的会话再删。');
      return false;
    }
    bool known;
    try {
      known =
          _sessions.get(id) != null ||
          (await _sessions.persistedIds()).contains(id);
    } catch (error) {
      showSystemNotice('读取会话列表失败：$error');
      return false;
    }
    if (!known) {
      showSystemNotice('会话 $id 不存在。');
      return false;
    }
    final List<String> errors = <String>[];
    await _attemptDelete(errors, '会话数据', () async {
      await _sessions.flush();
      await _sessions.remove(id);
    });
    errors.addAll(await _clearSessionArtifacts(id));
    if (errors.isEmpty) {
      _dropDeletedTab(id);
      transcript.add(TuiRole.system, '已删除会话 $id（数据与检查点已清理；导出文件保留）。');
    } else {
      showSystemNotice('删除会话 $id 未完全成功：${errors.join('；')}');
    }
    if (picker.open) {
      await picker.show(_sessionId);
    }
    _refresh();
    return errors.isEmpty;
  }

  /// 删除会话后清掉它的标签（当前会话禁止删除，故只会是非活跃标签）。
  void _dropDeletedTab(String id) {
    final int index = tabs.indexOf(id);
    if (index >= 0 && index != tabs.active) {
      tabs.close(index);
    }
  }

  /// 清检查点与故事线日志；每步独立捕获，返回失败说明。
  Future<List<String>> _clearSessionArtifacts(String id) async {
    final List<String> errors = <String>[];
    final CheckpointManager? checkpoint = _app.get<CheckpointManager>(
      'checkpointManager',
    );
    if (checkpoint != null) {
      await _attemptDelete(errors, '检查点', () => checkpoint.clearSession(id));
    }
    // 不看当前 `storyEnabled`：关闭故事层后仍可能有历史日志要清。服务未
    // 装配时退回目录服务直接删文件（文件名与会话 id 一一对应）。
    final SessionLog? log = _app.get<SessionLog>('sessionLog');
    if (log != null) {
      await _attemptDelete(errors, '故事线日志', () => log.remove(id));
    } else {
      final String? dir = _app.get<String>('storyLogDir');
      final File file = File('${dir ?? ''}${Platform.pathSeparator}$id.jsonl');
      if (dir != null && file.existsSync()) {
        await _attemptDelete(errors, '故事线日志', () async => file.delete());
      }
    }
    return errors;
  }

  /// 执行删除的一步；失败记进 [errors]，不中断后续清理。
  Future<void> _attemptDelete(
    List<String> errors,
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      errors.add('$label：$error');
    }
  }

  /// 确认选择：切到选中会话并关闭面板。
  Future<void> pickSelected() async {
    final String? id = picker.selectedId();
    picker.close();
    if (id != null) {
      await switchSession(id);
    }
  }

  /// 切换会话：不存在则懒建（各自文件与历史）；非法 id 只提示不切换。
  ///
  /// busy（有在途轮次）时拒绝并返回 `false`：此时释放会话子上下文会把正在
  /// 跑的 Agent Loop 从脚下抽走，`/undo`、`/redo` 这类编排也据此判定未生效。
  /// 撤销/重做自身（[_revertInFlight]）不受此限——它就是那条编排。
  ///
  /// [system] 供撤销 / 重做 / rewind / 故事分叉等系统流程使用：标签满额时
  /// 挤掉一个非活跃标签腾位，而不是让核心流程失败。
  Future<bool> switchSession(
    String id, {
    String? announce,
    bool system = false,
  }) => _switchSession(
    id,
    announce: announce,
    saveTabScroll: true,
    system: system,
  );

  /// 是否正在用 ↑/↓ 浏览输入历史。
  bool get inputHistoryActive => _historyIndex >= 0;

  /// 取上一条输入；[draft] 是开始浏览前的输入框内容。
  String? previousInput(String draft) {
    final List<String> history = _uiState.history;
    if (history.isEmpty) return null;
    if (_historyIndex < 0) {
      _historyDraft = draft;
      _historyIndex = history.length - 1;
    } else if (_historyIndex > 0) {
      _historyIndex--;
    }
    return history[_historyIndex];
  }

  /// 取下一条输入；越过最后一条时返回浏览前的草稿。
  String? nextInput() {
    final List<String> history = _uiState.history;
    if (_historyIndex < 0 || history.isEmpty) return null;
    if (_historyIndex < history.length - 1) {
      _historyIndex++;
      return history[_historyIndex];
    }
    _historyIndex = -1;
    final String draft = _historyDraft;
    _historyDraft = '';
    return draft;
  }

  /// 退出历史浏览（提交、编辑输入后调用）。
  void resetInputHistory() {
    _historyIndex = -1;
    _historyDraft = '';
  }

  /// 记录聊天滚动位置并落盘；由视图在离开标签 / 退出时调用。
  void recordScroll(double offset) {
    tabs.saveScroll(offset);
    _uiState = _uiState.withScroll(offset);
    _persistUiState();
  }

  /// 立即把当前 UI 状态写入 sidecar；无存储服务时只保留内存态。
  void persistUiState() => _persistUiState();

  void _recordInput(String text) {
    _resetHistoryNavigation();
    _uiState = _uiState.withInput(text);
    _persistUiState();
  }

  void _resetHistoryNavigation() {
    _historyIndex = -1;
    _historyDraft = '';
  }

  void _persistUiState() {
    final SessionUiStateStore? store = _app.get<SessionUiStateStore>(
      'sessionUiState',
    );
    if (store == null || _sessionId.isEmpty) return;
    unawaited(store.save(_sessionId, _uiState).catchError((Object _) {}));
  }

  SessionUiStateStore? get _uiStore =>
      _app.get<SessionUiStateStore>('sessionUiState');

  /// 切换会话的实现；[saveTabScroll] 为 `false` 时由调用方已保存滚动位置
  /// （关闭活跃标签后目标标签的偏移不能被当前会话的位置覆盖）。
  Future<bool> _switchSession(
    String id, {
    String? announce,
    required bool saveTabScroll,
    bool system = false,
  }) async {
    final String? blocked = _blockedSwitchReason(id);
    if (blocked != null) {
      transcript.add(TuiRole.system, blocked);
      _refresh();
      return false;
    }
    if (!_tabSlotAvailable(id, system: system)) {
      showSystemNotice('最多 $kTabCap 个标签；先关闭一个标签再打开新会话。');
      return false;
    }
    final String previous = _sessionId;
    if (saveTabScroll) onTabLeave?.call();
    // 显式切会话即放弃撤销点：`RevertStage` 跨会话存活会让用户在别的会话里
    // `/redo`，用另一个会话的快照覆盖当前工作区（撤销后新建的文件会被删）。
    // `/undo` / `/redo` 自身在切换后重新设置 / 清空它，不受影响。
    _revertStage = null;
    _prefill = null;
    _unbind();
    _sessionId = id;
    try {
      await _bind(id);
    } catch (error) {
      return _recoverSession(previous, id, error);
    }
    await _restoreBoundAgentModel();
    _syncTabState();
    _restoreActiveScroll();
    transcript.add(
      TuiRole.system,
      announce ?? '已切换到会话 $_sessionId（数据文件：$_sessionId.jsonl）。',
    );
    _refresh();
    return true;
  }

  /// 切换会话的前置拒绝原因；可切换时返回 `null`。
  String? _blockedSwitchReason(String id) {
    if (busy && !_revertInFlight) {
      return '有在途轮次，请稍候再试。';
    }
    if (!isValidSessionId(id)) {
      return '会话 id 非法：只允许字母/数字/下划线/中文/短横，长度 1—64。';
    }
    if (ready && id == _sessionId) {
      return '已在会话 $_sessionId。';
    }
    return null;
  }

  /// 目标会话是否已有标签名额；[system] 流程满额时挤掉非活跃标签。
  bool _tabSlotAvailable(String id, {required bool system}) {
    if (tabs.contains(id) || tabs.canAdd) {
      return true;
    }
    return system && tabs.evictInactive();
  }

  /// 目标标签有保存过的滚动位置时恢复；新标签跳到会话末尾（不是顶部）。
  void _restoreActiveScroll() {
    final double? pending = _pendingScroll;
    _pendingScroll = null;
    onTabRestore?.call(
      pending ??
          (tabs.activeScrollSaved ? tabs.restoreScroll() : double.infinity),
    );
  }

  /// 目标会话读取失败（JSONL 损坏等）：回绑原会话并留在原标签。
  Future<bool> _recoverSession(
    String previous,
    String failedId,
    Object error,
  ) async {
    _unbind();
    _sessionId = previous;
    await _rebindPrevious(previous);
    _syncTabState();
    _restoreActiveScroll();
    showSystemNotice('会话 $failedId 读取失败（数据可能损坏），已留在会话 $_sessionId：$error');
    return false;
  }

  /// 回绑原会话；原会话也读不出来时退到一个全新会话（失败只提示）。
  Future<void> _rebindPrevious(String previous) async {
    try {
      await _bind(previous);
    } catch (error) {
      await _bindFallbackSession(previous, error);
    }
  }

  /// 激活指定标签；切换被 busy 拒绝时返回 `false`。
  Future<bool> activateTab(int index) async {
    if (index < 0 || index >= tabs.tabs.length) return false;
    if (index == tabs.active) return true;
    return switchSession(tabs.tabs[index].sessionId);
  }

  /// 切到下一个标签（循环）。
  Future<bool> activateNextTab() => _stepTab(1);

  /// 切到上一个标签（循环）。
  Future<bool> activatePreviousTab() => _stepTab(-1);

  Future<bool> _stepTab(int delta) {
    final int count = tabs.tabs.length;
    if (count < 2) return Future<bool>.value(false);
    final int next = (tabs.active + delta + count) % count;
    return activateTab(next);
  }

  /// 关闭当前标签。
  Future<bool> closeActiveTab() => closeTab(tabs.active);

  /// 关闭标签：只移除视图态，不删除会话数据。
  Future<bool> closeTab(int index) async {
    if (index < 0 || index >= tabs.tabs.length) return false;
    final bool removingActive = index == tabs.active;
    if (removingActive && (busy || _revertInFlight)) {
      showSystemNotice('有在途轮次，请稍候再试。');
      return false;
    }
    final String removed = tabs.tabs[index].sessionId;
    if (removingActive) onTabLeave?.call();
    tabs.close(index);
    if (!removingActive) {
      _refresh();
      return true;
    }
    return _switchAfterClose(removed);
  }

  /// 关闭活跃标签后切到邻居；关掉最后一个时开一个新会话补位。
  Future<bool> _switchAfterClose(String removed) async {
    if (tabs.tabs.isEmpty) {
      final Session session = _sessions.create();
      final bool switched = await _switchSession(
        session.id,
        announce: '已关闭最后一个标签，开启新会话 ${session.id}。',
        saveTabScroll: false,
      );
      if (!switched) {
        await _sessions.remove(session.id);
      }
      return switched;
    }
    final String target = tabs.tabs[tabs.active].sessionId;
    final bool switched = await _switchSession(
      target,
      announce: '已关闭标签 $removed，切到会话 $target。',
      saveTabScroll: false,
    );
    if (!switched) {
      _syncTabState();
      _refresh();
    }
    return switched;
  }

  /// 开启新会话。
  Future<void> newSession() async {
    if (busy || _revertInFlight) {
      showSystemNotice('有操作进行中，请稍候再试。');
      return;
    }
    if (!tabs.canAdd) {
      showSystemNotice('最多 $kTabCap 个标签；先关闭一个标签再开新会话。');
      return;
    }
    final Session session = _sessions.create();
    final bool switched = await switchSession(
      session.id,
      announce: '已开启新会话 ${session.id}（上一会话已保存，/sessions 可切回）。',
    );
    if (switched) return;
    // 没切过去就别留下没人用的空会话（数据文件与仓库条目都撤掉）。
    await _sessions.remove(session.id);
    showSystemNotice('新会话未开启：切换被拒绝。');
  }

  Future<void> _handleCommand(String command, String arg) async {
    final WorkspaceInfo? activeInfo = _app.get<WorkspaceInfo>('projectInfo');
    final ProjectRegistry? activeRegistry = _app.get<ProjectRegistry>(
      'projectRegistry',
    );
    if (activeInfo != null && activeRegistry != null) {
      activeRegistry.touchProject(activeInfo.projectId);
    }
    switch (command) {
      case 'quit' || 'exit':
        onExit?.call();
      case 'help':
        transcript.openHelp(
          buildTuiHelpText(
            extra: <TuiCommand>[..._skillCommands, ..._customCommands],
          ),
        );
      case 'new':
        await newSession();
      case 'agents':
        openAgentPicker();
      case 'sessions':
        await openPicker();
      case 'project':
        _handleProject(arg);
      case 'lsp':
        await _handleLsp(arg);
      case 'web':
        _handleWeb();
      case 'projects':
        await _handleProjects();
      case 'worktree':
        await _handleWorktree(arg);
      case 'rename':
        await _handleRename(arg);
      case 'session':
        if (arg.isEmpty) {
          await openPicker();
        } else {
          await switchSession(arg);
        }
      case 'tools':
        _showTools();
      case 'reload':
        await reloadDefinitions();
      case 'mcp':
        _showMcp();
      case 'model':
        await _handleModel(arg);
      case 'provider':
        await _handleProvider(arg);
      case 'permission':
        await _handlePermission();
      case 'theme':
        await _handleTheme();
      case 'plan':
        _openPlanPanel();
      case 'goal':
        await _handleGoal(arg);
      case 'init':
        await _handleInit();
      case 'commit':
        await _handleCommit();
      case 'review':
        await _handleReview();
      case 'compact':
        await _handleCompact();
      case 'rewind':
        await _handleRewind(arg);
      case 'undo':
        await _runUndoArg(arg);
      case 'redo':
        await redo();
      case 'diff':
        await _handleDiff(arg);
      case 'background':
        await _handleBackground(arg);
      case 'doctor':
        _showDoctor();
      case 'story':
        await _handleStory(arg);
      case 'cost':
        _showCost();
      case 'cron':
        await _handleCron(arg);
      case 'team':
        await _handleTeam(arg);
      case 'task':
        await _handleTask(arg);
      case 'remember':
        await _remember(arg);
      case 'forget':
        await _forget(arg);
      case 'telemetry':
        _showTelemetry();
      case 'trace':
        _showTrace(arg);
      case 'export':
        await _exportSession(arg);
      case 'clear':
        transcript.clear();
      case 'keybinds':
        transcript.add(TuiRole.system, renderKeybinds(keymap));
      case 'settings':
        openSettings();
      default:
        // 内置命令优先；未命中再查自定义命令，最后才把命令词当技能名试一次。
        if (!await runCustomCommand(command, arg) &&
            !await _runSkill(command, arg)) {
          transcript.add(TuiRole.system, '未知命令：/$command（/help 查看可用命令）');
        }
    }
    _refresh();
  }

  /// 当前可用的斜杠命令：静态表 + 技能注册表投影 + 自定义命令。
  ///
  /// 内置命令排在最前；与内置 / 技能同名的自定义命令不进入菜单（执行时同样
  /// 被内置命令挡住）。
  List<TuiCommand> get commands => <TuiCommand>[
    ...tuiCommands,
    ..._skillCommands,
    ..._customCommands,
  ];

  List<TuiCommand> get _skillCommands =>
      skillTuiCommands(_app.get<SkillRegistry>('skillRegistry'));

  /// 技能命令命名空间；自定义命令不得占用（菜单隐藏、分发也不拦截技能）。
  bool _isSkillCommandName(String name) =>
      name == 'skill' || name.startsWith(kTuiSkillCommandPrefix);

  List<TuiCommand> get _customCommands {
    final CommandDispatcher? dispatcher = _dispatcher;
    if (dispatcher == null) return const <TuiCommand>[];
    final Set<String> reserved = <String>{
      for (final TuiCommand command in tuiCommands) command.name,
      for (final TuiCommand command in _skillCommands) command.name,
      'quit',
    };
    return <TuiCommand>[
      for (final CommandDefinition def in dispatcher.all)
        if (!reserved.contains(def.name) && !_isSkillCommandName(def.name))
          TuiCommand(
            name: def.name,
            description: dispatcher.menuDescription(def),
          ),
    ];
  }

  /// 构造分发器；命令 / Agent 注册表任一缺失时返回 `null`（功能降级）。
  CommandDispatcher? get _dispatcher {
    final CommandRegistry? registry = _commandRegistry;
    final AgentRegistry? agents = _agentRegistry;
    if (registry == null || agents == null) return null;
    return CommandDispatcher(
      registry: registry,
      agents: agents,
      providers: _app.providers,
      runShell: _runCommandShell,
    );
  }

  /// 展开命令模板时的 shell 块执行：走**沙箱** `shell` 缝（仓库里的命令文件
  /// 属于不可信输入，不能借用用户直发的 `shellInteractive`），失败即抛出。
  Future<String> _runCommandShell(String command) async {
    final ShellExecutor? shell = _app.get<ShellExecutor>('shell');
    if (shell == null) {
      throw StateError('shell 不可用');
    }
    final ShellRunResult result = await shell.run(
      shell.resolve(
        ShellExecRequest(command: command, timeoutMs: kShellBangTimeoutMs),
      ),
    );
    if (result.timedOut) {
      throw StateError('命令超时（${kShellBangTimeoutMs ~/ 1000}s）');
    }
    final int? code = result.exitCode;
    if (code == 0) return result.stdout.text;
    final String body = _joinedOutput(result.stdout.text, result.stderr.text);
    final String status = code == null ? '未知退出码（可能超时）' : 'exit $code';
    throw StateError('命令失败（$status）：${_capCommandOutput(body)}');
  }

  /// 合并 stdout / stderr：优先保留非空侧，两侧都有时换行拼接。
  String _joinedOutput(String out, String err) {
    if (out.isEmpty) return err;
    if (err.isEmpty) return out;
    return '$out\n$err';
  }

  /// 截断 shell 失败输出，避免一段构建日志把提示刷出屏幕。
  String _capCommandOutput(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return '（无输出）';
    final Runes runes = trimmed.runes;
    if (runes.length <= kCommandFailureLimit) return trimmed;
    return '${String.fromCharCodes(runes.take(kCommandFailureLimit))}…（已截断）';
  }

  /// 执行一条自定义命令；不是自定义命令时返回 `false`（调用方继续兜底）。
  ///
  /// 展开失败（含 shell 块失败）只上屏提示，不提交任何 prompt。
  Future<bool> runCustomCommand(String name, String args) async {
    final CommandDispatcher? dispatcher = _dispatcher;
    final CommandDefinition? def = dispatcher?.byName(name);
    if (def == null || _isSkillCommandName(name)) return false;
    if (busy || _revertInFlight) {
      showSystemNotice('有操作进行中，命令 /$name 稍后再试。');
      return true;
    }
    if (!ready || _agent == null) {
      showSystemNotice('会话尚未就绪，命令 /$name 未执行。');
      return true;
    }
    final String prompt;
    try {
      prompt = await dispatcher!.expand(def, args);
    } catch (error) {
      showSystemNotice('命令 /$name 展开失败：$error');
      return true;
    }
    if (prompt.trim().isEmpty) {
      showSystemNotice('命令 /$name 没有可提交的内容。');
      return true;
    }
    if (def.subagent) {
      await _runCommandSubagent(name, def, prompt);
      return true;
    }
    await _applyCommandOverrides(def);
    transcript.add(TuiRole.system, '已展开自定义命令 /$name。');
    await submit(prompt);
    // submit 提前返回（会话刚好未就绪等）时不会经过 _afterTurn，这里兜底还原。
    if (_turnOverride != null) await _restoreTurnOverride();
    return true;
  }

  /// 自定义命令的 `subagent: true`：前台调用 `task`，结果写入记录。
  ///
  /// 与普通对话轮次一样占用 [busy]、登记取消句柄：期间新输入排队，Esc 会
  /// 同时取消等待与真正的 `SpawnAgentTool`。
  Future<void> _runCommandSubagent(
    String name,
    CommandDefinition def,
    String prompt,
  ) async {
    final ToolRegistry tools = _app.tools;
    final Tool? tool = tools.get('task');
    if (tool == null) {
      showSystemNotice('命令 /$name 需要 task，但当前未装配。');
      return;
    }
    if (def.model != null && def.model!.trim().isNotEmpty) {
      // 子 Agent 的模型由 Agent profile（`agent:` 对应定义）决定，task
      // 没有单次 model 参数：明确告知而不是静默忽略。
      showSystemNotice(
        '命令 /$name 的 model: ${def.model} 对子 Agent 不生效；'
        '请给 agent 定义设置 model，或改用普通命令。',
      );
    }
    final Session? session = _session;
    // 命令同样是一轮用户输入：写进会话，重开 / 导出时才看得到上下文。
    session?.append(kUserMessageEvent, data: <String, Object?>{'text': prompt});
    // 工具结果必须有配对的 assistant tool_calls：否则下次压缩的配对检查
    // （balancedCutAtOrBefore）会看到孤立结果直接失败，且这个断点会落盘。
    final String callId = 'command-$name';
    session?.append(
      kAssistantMessageEvent,
      data: <String, Object?>{
        'text': '',
        'toolCalls': toolCallsToJson(<LlmToolCall>[
          LlmToolCall(id: callId, name: 'task'),
        ]),
      },
    );
    final AgentCancel cancel = AgentCancel();
    _cancel = cancel;
    _foregroundInterrupt = () {
      cancel.cancel();
      if (tool is SpawnAgentTool) tool.interrupt();
    };
    _beginTurn();
    busy = true;
    bool turnOk = true;
    bool interrupted = false;
    bool budgetExhausted = false;
    transcript.add(TuiRole.system, '命令 /$name 以前台子 Agent 执行，请稍候。');
    _refresh();
    try {
      ToolResult result;
      try {
        result = await Future.any<ToolResult>(<Future<ToolResult>>[
          tools.call(
            ToolCall(
              name: 'task',
              arguments: <String, Object?>{
                'task': prompt,
                if (def.agent != null) 'agent': def.agent,
              },
            ),
          ),
          cancel.whenCancelled.then((_) => ToolResult.failure('已打断')),
        ]);
      } catch (error) {
        result = ToolResult.failure('子 Agent 执行异常：$error');
      }
      // 取消 / 异常也写结果：assistant tool_calls 一旦落盘就必须闭合，
      // 否则会话在后续压缩时永久失衡。
      interrupted = cancel.cancelled;
      budgetExhausted = result.content == kBudgetExhaustedReply;
      turnOk = !interrupted && !result.isError && !budgetExhausted;
      session?.append(
        kToolResultEvent,
        data: <String, Object?>{
          'callId': callId,
          'name': 'task',
          'content': interrupted ? '已打断' : result.content,
          'isError': interrupted || result.isError,
        },
      );
      if (interrupted) {
        transcript.add(TuiRole.system, '已打断这一轮。');
        return;
      }
      if (result.isError) {
        showSystemNotice('子 Agent 执行失败：${result.content}');
      }
    } finally {
      _foregroundInterrupt = null;
      _cancel = null;
      busy = false;
      _endTurn(ok: turnOk, interrupted: interrupted, budget: budgetExhausted);
      await _afterTurn();
      _refresh();
    }
  }

  /// 应用命令声明的 Agent / 模型覆盖，并登记本轮结束后的还原点。
  ///
  /// Agent 切换**不动**手动 Plan Mode（只有 `agent: plan` 会补进入）；所有
  /// 改动合并到一次 rebind，避免 agent + model 双重重绑。
  Future<void> _applyCommandOverrides(CommandDefinition def) async {
    if (def.agent == null && def.model == null) return;
    final _ModelChoice current = _currentModelChoice();
    final _TurnOverride restore = _TurnOverride(
      agentId: _agentId,
      entries: current.entries,
      modelLabel: current.label,
      planModeActive: planModeActive,
    );
    bool applied = false;
    if (def.agent != null) {
      applied = await _activateAgent(
        def.agent!,
        announce: false,
        syncPlanMode: false,
        rebindNow: false,
      );
      if (!applied) {
        showSystemNotice('Agent ${def.agent} 不可用，沿用当前 Agent。');
      }
    }
    if (def.model != null) {
      if (restore.entries.isEmpty) {
        showSystemNotice('当前没有可用模型链，模型覆盖已跳过。');
      } else {
        final String? warning = await _applyModelSpec(
          def.model!,
          rebindNow: false,
        );
        if (warning != null) {
          showSystemNotice('$warning，沿用当前模型。');
        } else {
          applied = true;
        }
      }
    }
    if (!applied) return;
    _turnOverride = restore;
    await _rebindAs(_agentId);
    // rebind 会 dispose 旧 PlanMode（active 时会写 inactive 事件）；按本轮
    // 期望状态恢复：手动 Plan Mode 原样保留，`agent: plan` 补进入。
    if (restore.planModeActive || def.agent == 'plan') {
      _setPlanMode(true);
    }
  }

  /// 按 `provider[/model]` 临时替换 LLM 链；失败返回可展示原因。
  Future<String?> _applyModelSpec(String spec, {bool rebindNow = true}) async {
    final ProviderRegistry? registry = _app.providers;
    if (registry == null) return '未装配模型提供商';
    final int slash = spec.indexOf('/');
    final String provider = (slash < 0 ? spec : spec.substring(0, slash))
        .trim();
    final String? rawModel = slash < 0
        ? null
        : spec.substring(slash + 1).trim();
    final String? typedModel = rawModel == null
        ? null
        : stripModelVariant(rawModel);
    final ProviderProfile? profile = registry.byName(provider);
    if (profile == null) return '未知提供商：$provider';
    final String label = (typedModel != null && typedModel.isNotEmpty)
        ? typedModel
        : (profile.defaultModel ?? '');
    if (label.isEmpty) return '提供商 $provider 没有可用模型';
    final LlmChain? chain = buildLlmChain(
      registry,
      entries: <String>['$provider/$label', ..._fallbackModels],
      policy: _retryPolicy,
      notices: _app.get<LlmNotices>('llmNotices'),
    );
    final LlmChainSlot? slot = _app.get<LlmChainSlot>('llmChainSlot');
    final void Function(FallbackLlm)? swap = switchLlm;
    if (chain == null) return '没有可用模型：$provider/$label';
    if (slot == null || swap == null) return '模型切换未装配';
    slot.current = chain;
    swap(chain.llm);
    modelLabel = label;
    if (rebindNow) await rebind();
    return null;
  }

  /// 按候选清单切换到已记录的模型（不负责 rebind）。
  bool _applyModelChoice(_ModelChoice choice) {
    if (choice.entries.isEmpty) return false;
    final ProviderRegistry? registry = _app.providers;
    final LlmChainSlot? slot = _app.get<LlmChainSlot>('llmChainSlot');
    final void Function(FallbackLlm)? swap = switchLlm;
    if (registry == null || slot == null || swap == null) return false;
    final LlmChain? chain = buildLlmChain(
      registry,
      entries: choice.entries,
      policy: _retryPolicy,
      notices: _app.get<LlmNotices>('llmNotices'),
    );
    if (chain == null) return false;
    slot.current = chain;
    swap(chain.llm);
    modelLabel = choice.label;
    return true;
  }

  /// 切到没有 `model:` 的 Agent 时回到非 Agent 模型基线。
  bool _restoreBaselineModel() {
    final _ModelChoice? baseline = _modelBaseline;
    return baseline == null ? false : _applyModelChoice(baseline);
  }

  /// 本轮结束后还原自定义命令的 Agent / 模型 / Plan Mode 覆盖。
  Future<void> _restoreTurnOverride() async {
    final _TurnOverride? restore = _turnOverride;
    if (restore == null) return;
    _turnOverride = null;
    _agentId = restore.agentId;
    _applyModelChoice(
      _ModelChoice(entries: restore.entries, label: restore.modelLabel),
    );
    // rebind 会清空排队输入；还原期间先把队列存下来，成功重绑后再放回，
    // 让本轮结束后原本排队的消息照常投递。
    final List<(String, List<TuiAttachment>)> pending =
        List<(String, List<TuiAttachment>)>.of(_queue);
    if (ready && !busy) {
      final bool rebound = await rebind();
      if (rebound) _queue.addAll(pending);
    }
    _setPlanMode(restore.planModeActive);
  }

  /// `/agents`：打开 Agent 选择面板。
  /// `/settings`：打开设置面板。
  void openSettings() => settingsPrompt.openPanel();

  /// Esc：关闭设置面板。
  void closeSettings() => settingsPrompt.close();

  /// ↑ / ↓：移动选中项。
  void moveSettings(int delta) => settingsPrompt.move(delta);

  /// ← / →：翻页。
  void pageSettings(int delta) => settingsPrompt.pageBy(delta);

  /// Enter：关闭面板并执行选中项对应的命令。
  Future<void> selectSettings() async {
    final String command = settingsPrompt.selected.command;
    settingsPrompt.close();
    await handleLine(command);
  }

  void openAgentPicker() {
    final AgentRegistry? registry = _agentRegistry;
    if (registry == null) {
      showSystemNotice('Agent 注册表未装配，无法选择 Agent。');
      return;
    }
    agentPicker.show(registry, currentId: _agentId);
  }

  /// 关闭 Agent 选择面板。
  void closeAgentPicker() => agentPicker.close();

  /// 移动 Agent 选择面板光标。
  void moveAgentPicker(int delta) => agentPicker.move(delta);

  /// 确认 Agent 选择：仅子 Agent 条目只提示，不切换。
  Future<void> pickAgent() async {
    final AgentDefinition? agent = agentPicker.selectedAgent;
    final AgentDefinition? blocked = agentPicker.focused;
    agentPicker.close();
    if (agent == null) {
      showSystemNotice(
        blocked == null ? '没有可切换的 Agent。' : '${blocked.id} 只能作为子 Agent 使用。',
      );
      return;
    }
    await switchAgent(agent.id);
  }

  /// 切换当前会话 Agent：重建 system prompt / 模型 / 权限作用域。
  Future<bool> switchAgent(String id) async {
    if (busy || _revertInFlight) {
      showSystemNotice('有操作进行中，请稍候再切换 Agent。');
      return false;
    }
    final AgentDefinition? def = _agentRegistry?.byId(id);
    if (def == null) {
      showSystemNotice('未知 Agent：$id');
      return false;
    }
    if (def.mode == AgentMode.subagent) {
      showSystemNotice('Agent ${def.id} 只能作为子 Agent 使用。');
      return false;
    }
    await _activateAgent(def.id, announce: true);
    return true;
  }

  /// 激活 Agent：换模型（无 `model:` 时回到基线），重绑会话并按需同步 Plan Mode。
  Future<bool> _activateAgent(
    String id, {
    required bool announce,
    bool syncPlanMode = true,
    bool rebindNow = true,
  }) async {
    final AgentDefinition? def = _agentRegistry?.byId(id);
    if (def == null || def.mode == AgentMode.subagent) return false;
    _agentId = def.id;
    if (def.model != null) {
      final String? warning = await _applyModelSpec(
        def.model!,
        rebindNow: false,
      );
      if (warning != null) {
        showSystemNotice('Agent ${def.id} 的模型不可用：$warning，沿用当前模型。');
      }
    } else {
      _restoreBaselineModel();
    }
    // 显式切换才写会话事件；自定义命令的临时覆盖（announce=false）不能改写
    // 会话归属，否则本轮结束后还原的是「命令里的 Agent」。
    if (announce) _persistAgentSelection();
    if (rebindNow) await _rebindAs(def.id);
    if (syncPlanMode) _syncAgentPlanMode(def.id);
    if (announce) showSystemNotice('已切换到 Agent「${def.id}」。');
    return true;
  }

  /// `plan` 进入 Plan Mode，`build` 退出；其余 Agent 不改动 Plan Mode。
  void _syncAgentPlanMode(String id) {
    if (id == 'plan') {
      _setPlanMode(true);
    } else if (id == 'build') {
      _setPlanMode(false);
    }
  }

  /// 新会话的欢迎信息：目录 / 会话 / 模型 / 版本 / MCP，以及连接明细。
  ///
  /// 只在新建会话时显示；`--session` / `--continue` 恢复会话时保持安静。
  void _addStartupBanner() {
    final McpRegistry? registry = _app.get<McpRegistry>('mcp');
    final List<String> servers = registry?.servers ?? const <String>[];
    final String workdir =
        _app.get<String>('workdir') ?? Directory.current.path;
    final List<String> rows = <String>[
      'Welcome to nava!',
      'Send /help for help information.',
      '',
      'Directory: $workdir',
      'Session:   $_sessionId',
      'Model:     $modelLabel',
      'Version:   $navaVersion',
      'MCP:       ${servers.length} connected',
    ];
    final int width =
        rows
            .map((String row) => row.length)
            .reduce((int a, int b) => a > b ? a : b) +
        2;
    final StringBuffer box = StringBuffer()..writeln('╭${'─' * width}╮');
    for (final String row in rows) {
      box.writeln('│ ${row.padRight(width - 1)}│');
    }
    box.writeln('╰${'─' * width}╯');
    final List<String> footer = <String>[
      'Started a new session ($_sessionId).',
      for (final String server in servers)
        'MCP server "$server" connected · '
            '${registry!.toolsOf(server).length} tools',
    ];
    transcript.add(TuiRole.system, '${box.toString()}\n${footer.join('\n')}');
  }

  /// 启动默认 Plan Mode：会话没有历史 `plan/mode` 事件时才生效。
  void _applyStartInPlanMode() {
    if (!startInPlanMode) return;
    final bool hasEvent =
        _session?.ownEvents.any(
          (SessionEvent event) => event.type == kPlanModeEvent,
        ) ??
        false;
    if (!hasEvent) _setPlanMode(true);
  }

  /// 显式设置 Plan Mode；无绑定时静默忽略。
  void _setPlanMode(bool active) {
    final PlanMode? planMode = _planMode;
    if (planMode == null) return;
    if (active) {
      if (planMode.state != PlanModeState.active) {
        planMode.enter();
        _refresh();
      }
      return;
    }
    if (planMode.state == PlanModeState.active) {
      planMode.exit();
      _refresh();
    }
  }

  /// 把 `/skill:<技能名> [补充要求]` 当作技能调用；不是 `skill:` 前缀命令时
  /// 返回 `false`（裸 `/skill` 给用法提示）。
  ///
  /// 展开后的正文块作为一轮用户输入交给 Agent Loop，因此照常进
  /// `user/message` 事件；屏上由 [collapseSkillPrompt] 折叠回一行。
  Future<bool> _runSkill(String command, String arg) async {
    if (command == 'skill') {
      transcript.add(TuiRole.system, kTuiSkillUsage);
      return true;
    }
    if (!command.startsWith(kTuiSkillCommandPrefix)) return false;
    final String name = command.substring(kTuiSkillCommandPrefix.length);
    final SkillRegistry? registry = _app.get<SkillRegistry>('skillRegistry');
    if (registry == null) return false;
    final SkillDefinition? definition = await registry.load(name);
    if (definition == null) return false;
    transcript.add(TuiRole.system, '已展开技能 `$name`，交给模型执行。');
    await submit(renderSkillPrompt(definition, arg));
    return true;
  }

  void _showTools() {
    final ToolRegistry? tools = _app.get<ToolRegistry>('tools');
    if (tools == null || tools.names.isEmpty) {
      transcript.add(TuiRole.system, '当前没有已注册工具。');
      return;
    }
    transcript.add(
      TuiRole.system,
      '已注册工具（${tools.names.length}）：${tools.names.join('、')}',
    );
  }

  /// `/mcp`：列出已接入的 MCP server 与各自工具数（不经模型，只读）。
  void _showMcp() {
    final McpRegistry? registry = _app.get<McpRegistry>('mcp');
    if (registry == null || registry.servers.isEmpty) {
      transcript.add(
        TuiRole.system,
        '未配置 MCP server（config.toml [mcp.servers.*]）。',
      );
      return;
    }
    final StringBuffer buffer = StringBuffer(
      '已接入 MCP server（${registry.servers.length}）：',
    );
    for (final String name in registry.servers) {
      final McpClient? client = registry.clientOf(name);
      final String state = client == null || !client.ready ? '未就绪' : '就绪';
      buffer.write('\n  $name［$state］工具 ${registry.toolsOf(name).length} 个');
    }
    transcript.add(TuiRole.system, buffer.toString());
  }

  /// `/model [名字]` 与 `/provider` 的实现见 part 文件
  /// `tui_controller_provider.dart`。

  /// provider 浮层 Enter：选中新增入口时打开表单（根组件按键调用）。
  Future<void> confirmProviderItem() => _confirmProviderItem();

  /// Plan 面板 Enter：切换 Plan Mode 并刷新面板（根组件按键调用）。
  Future<void> confirmPlanPanel() => _confirmPlanPanel();

  /// `/plan`：进入 / 退出 Plan Mode（先规划、经 exit_plan_mode 提交后执行）。
  void _togglePlanMode() {
    final PlanMode? planMode = _planMode;
    if (planMode == null) {
      transcript.add(TuiRole.system, 'Plan Mode 不可用：会话尚未绑定。');
      return;
    }
    if (planMode.state == PlanModeState.active) {
      planMode.exit();
      transcript.add(TuiRole.system, '已退出 Plan Mode。');
      return;
    }
    planMode.enter();
    final String reviewNote = _app.has('approval')
        ? '计划经 exit_plan_mode 提交后等待审批。'
        : '计划经 exit_plan_mode 提交后即获批执行（未配置审批端口）。';
    transcript.add(
      TuiRole.system,
      '已进入 Plan Mode：有副作用的工具被拦截，模型先规划再执行。$reviewNote',
    );
  }

  /// `/compact`：手动压缩当前会话，把早期历史折叠成滚动摘要。
  ///
  /// 复用 Agent Loop 同款 LLM 汇总器（`summarizeEvents`），`keepRecent` 取
  /// [kManualCompactKeepRecent]（20 条）强制折叠；历史太短返回 `null` 不报错。
  Future<void> _handleCompact() async {
    final CompactionEngine? compactor = _app.get<CompactionEngine>(
      'compaction',
    );
    final Session? session = _session;
    final LlmProvider? llm = _app.get<LlmProvider>('llm');
    if (compactor == null || session == null || llm == null) {
      transcript.add(TuiRole.system, '压缩不可用：会话尚未就绪或未装配压缩服务。');
      return;
    }
    try {
      final CompactionResult? result = await compactor.compactIfNeeded(
        session,
        (List<SessionEvent> events, String previous) =>
            summarizeEvents(llm, events, previous),
        keepRecent: kManualCompactKeepRecent,
      );
      if (result == null) {
        transcript.add(TuiRole.system, '历史太短，无需压缩。');
        return;
      }
      transcript.add(TuiRole.system, '已压缩 ${result.compacted} 条早期事件。');
    } catch (error) {
      transcript.add(TuiRole.system, '压缩失败：$error');
    }
  }

  /// `/trace [N]`：复盘最近 N 轮（缺省 1）的事件时间线。
  ///
  /// 回答的是「模型当时看到了什么、为什么那么判断」——屏上只有结论，复盘给的是
  /// 过程。数据本来就是可读 JSONL，这里只是给个入口。
  void _showTrace(String arg) {
    final Session? session = _session;
    if (session == null) {
      transcript.add(TuiRole.system, '复盘不可用：会话尚未绑定。');
      return;
    }
    final String trimmed = arg.trim();
    final int? turns = trimmed.isEmpty ? null : int.tryParse(trimmed);
    if (trimmed.isNotEmpty && turns == null) {
      transcript.add(TuiRole.system, '/trace 的参数是轮数（正整数），收到 "$arg"。');
      return;
    }
    transcript.add(
      TuiRole.system,
      const TraceRenderer().render(session.events, turns: turns),
    );
  }

  /// `/export [路径]`：把当前会话导出为 markdown。
  ///
  /// 缺省落项目数据目录的 `exports/`（不在工作区留文件）；给路径则照写。
  Future<void> _exportSession(String arg) async {
    final Session? session = _session;
    if (session == null) {
      transcript.add(TuiRole.system, '导出不可用：会话尚未绑定。');
      return;
    }
    // 先落盘再提示——导出会新增事件，导出内容里不该包含「导出这条记录」。
    final String? path = await _writeExport(session, arg);
    if (path == null) return;
    transcript.add(TuiRole.system, '已导出：$path');
  }

  /// 写导出文件；失败时把错误上屏并返回 `null`。
  Future<String?> _writeExport(Session session, String arg) async {
    final CostTrackerImpl? tracker = _app.get<CostTrackerImpl>('costTracker');
    final SessionExport export = SessionExport(
      session: session,
      modelLabel: modelLabel,
      workdir: _app.get<String>('workdir') ?? '',
      cost: tracker?.todayCost ?? 0,
      promptTokens: tracker?.promptTokens ?? 0,
      completionTokens: tracker?.completionTokens ?? 0,
      rateSummary: tracker?.profile?.rateSummary ?? '未知',
    );
    try {
      return await export.write(
        target: arg.trim().isEmpty ? null : arg.trim(),
        projectDataDir: _projectDataDir(),
      );
    } on FileSystemException catch (error) {
      transcript.add(TuiRole.system, '导出失败：${error.message}（${error.path}）');
      return null;
    }
  }

  /// `/project` 重命名后的内存显示名；持久值在 SQLite 里。
  String? _projectName;

  /// 状态栏等项目展示用的项目名。
  String? get projectName =>
      _projectName ?? _app.get<WorkspaceInfo>('projectInfo')?.projectName;

  void _handleProject(String arg) {
    final WorkspaceInfo? info = _app.get<WorkspaceInfo>('projectInfo');
    final ProjectRegistry? registry = _app.get<ProjectRegistry>(
      'projectRegistry',
    );
    if (info == null || registry == null) {
      transcript.add(TuiRole.system, '项目注册表未启用。');
      return;
    }
    final String rest = arg.trim();
    if (rest.isEmpty) {
      transcript.add(
        TuiRole.system,
        '项目：${_projectName ?? info.projectName}\n'
        'ID：${info.projectShortId}\n'
        'worktree：${info.worktreePath}\n'
        'worktree ID：${info.worktreeId.substring(0, 8)}\n'
        '数据目录：${info.dataDir}',
      );
      return;
    }
    if (rest == 'prune' || rest.startsWith('prune ')) {
      final bool purge = rest.substring('prune'.length).trim() == '--purge';
      final int archived = registry.archiveMissing();
      final int purged = purge ? registry.purgeArchived() : 0;
      transcript.add(
        TuiRole.system,
        '已归档 $archived 个失效项目${purge ? '，删除 $purged 个归档项目' : ''}。',
      );
      return;
    }
    if (rest == 'unarchive' || rest.startsWith('unarchive ')) {
      final String selector = rest.substring('unarchive'.length).trim();
      final WorkspaceInfo? target = registry
          .list(includeArchived: true)
          .where(
            (WorkspaceInfo item) =>
                item.projectId == selector ||
                item.projectId.startsWith(selector) ||
                item.projectName == selector,
          )
          .firstOrNull;
      if (target == null) {
        transcript.add(TuiRole.system, '没有匹配的归档项目：$selector');
        return;
      }
      registry.setArchived(target.projectId, archived: false);
      transcript.add(TuiRole.system, '已恢复项目：${target.projectName}');
      return;
    }
    if (rest == 'icon' || rest.startsWith('icon ')) {
      final List<String> parts = rest.substring(4).trim().split(RegExp(r'\s+'));
      if (parts.isEmpty || parts.first.isEmpty) {
        transcript.add(TuiRole.system, '用法：/project icon <图标> [颜色]');
        return;
      }
      registry.setIcon(
        info.projectId,
        url: parts.first,
        color: parts.length > 1 ? parts[1] : null,
      );
      transcript.add(TuiRole.system, '项目图标已更新。');
      return;
    }
    if (rest == 'list') {
      final List<WorkspaceInfo> list = registry.list();
      final StringBuffer buffer = StringBuffer(
        '已登记 ${list.length} 个 worktree：',
      );
      for (final WorkspaceInfo item in list) {
        final String mark = item.worktreeId == info.worktreeId ? '*' : ' ';
        final String worktreeShort = item.worktreeId.substring(0, 8);
        buffer.write(
          '\n$mark ${item.projectName}  ${item.projectShortId}/$worktreeShort  '
          '${item.strategy ?? 'user'}  ${item.worktreePath}',
        );
      }
      transcript.add(TuiRole.system, buffer.toString());
      return;
    }
    if (rest == 'open' || rest.startsWith('open ')) {
      final String selector = rest.substring('open'.length).trim();
      _openProject(info, registry, selector);
      return;
    }
    if (rest != 'rename' && !rest.startsWith('rename ')) {
      transcript.add(
        TuiRole.system,
        '用法：/project [list|open <项目|短ID|路径>|rename <名字>|'
        'unarchive <项目|短ID>|icon <图标> [颜色]|prune [--purge]]',
      );
      return;
    }
    final String name = rest.substring('rename'.length).trim();
    if (name.isEmpty) {
      transcript.add(TuiRole.system, '用法：/project rename <名字>');
      return;
    }
    try {
      registry.rename(info.projectId, name, dataDir: info.dataDir);
      _projectName = name;
      transcript.add(TuiRole.system, '项目已重命名为「$name」。');
    } on ArgumentError catch (error) {
      transcript.add(TuiRole.system, '重命名失败：${error.message}');
    }
  }

  void _openProject(
    WorkspaceInfo current,
    ProjectRegistry registry,
    String selector,
  ) {
    if (selector.isEmpty) {
      transcript.add(TuiRole.system, '用法：/project open <项目名|短ID|路径>');
      return;
    }
    if (busy) {
      transcript.add(TuiRole.system, '有在途轮次，请稍候再试。');
      return;
    }
    final List<WorkspaceInfo> matches = registry
        .list(includeArchived: true)
        .where(
          (WorkspaceInfo item) =>
              item.worktreeId == selector ||
              item.projectId == selector ||
              item.worktreeId.startsWith(selector) ||
              item.projectId.startsWith(selector) ||
              item.projectName == selector ||
              item.worktreePath == selector,
        )
        .toList();
    if (matches.isEmpty) {
      transcript.add(TuiRole.system, '没有匹配的项目：$selector');
      return;
    }
    if (matches.length > 1) {
      transcript.add(
        TuiRole.system,
        '匹配到多个 worktree，请用 worktree 短 ID（/project list 查看）。',
      );
      return;
    }
    final WorkspaceInfo target = matches.single;
    if (target.worktreeId == current.worktreeId) {
      transcript.add(TuiRole.system, '已经在当前 worktree。');
      return;
    }
    if (!Directory(target.worktreePath).existsSync()) {
      transcript.add(TuiRole.system, '目标 worktree 不存在：${target.worktreePath}');
      return;
    }
    final void Function(String)? switchProject = onSwitchProject;
    if (switchProject == null) {
      transcript.add(TuiRole.system, '当前模式不支持项目切换。');
      return;
    }
    transcript.add(TuiRole.system, '正在切换到 ${target.projectName}…');
    switchProject(target.worktreePath);
  }

  void _handleWeb() {
    final SearchService? service = _app.get<SearchService>('search');
    if (service == null) {
      transcript.add(TuiRole.system, '搜索未装配。');
      return;
    }
    final List<SearchSourceStatus> all = service.allStatuses();
    if (all.isEmpty) {
      transcript.add(TuiRole.system, '没有可用的搜索源。');
      return;
    }
    final StringBuffer buffer = StringBuffer('搜索源：');
    for (final SearchSourceStatus status in all) {
      buffer.write('\n${status.name}  ${status.available ? '可用' : '不可用'}');
      if (status.reason.isNotEmpty) buffer.write('  ${status.reason}');
    }
    transcript.add(TuiRole.system, buffer.toString());
  }

  Future<void> _handleProjects() async {
    final WorkspaceInfo? info = _app.get<WorkspaceInfo>('projectInfo');
    final ProjectRegistry? registry = _app.get<ProjectRegistry>(
      'projectRegistry',
    );
    if (info == null || registry == null) {
      transcript.add(TuiRole.system, '项目注册表未启用。');
      return;
    }
    final List<WorkspaceInfo> list = registry.list(includeArchived: true);
    if (list.isEmpty) {
      transcript.add(TuiRole.system, '没有已登记项目。');
      return;
    }
    final String? selected = await choice.ask(
      TuiChoiceRequest(
        title: '项目',
        showRename: true,
        choices: <TuiChoice>[
          for (final WorkspaceInfo item in list)
            _projectChoice(registry, item, info.worktreeId),
        ],
      ),
    );
    if (selected == null) return;
    _openProject(info, registry, selected);
  }

  TuiChoice _projectChoice(
    ProjectRegistry registry,
    WorkspaceInfo item,
    String currentWorktreeId,
  ) {
    final ProjectRecord? project = registry.project(item.projectId);
    final String icon = project?.iconUrl ?? '';
    final bool archived = project?.timeArchived != null;
    return TuiChoice(
      id: item.worktreeId,
      label:
          '${icon.isEmpty ? '' : '$icon '}${item.projectName}'
          '${archived ? '  [已归档]' : ''}',
      description: item.worktreePath,
      current: item.worktreeId == currentWorktreeId,
      color: project?.iconColor,
    );
  }

  /// 项目面板按 `r`：当前项直接回填重命名命令；其他项先让用户切换。
  void renameSelectedProject() {
    final TuiChoiceRequest? request = choice.request;
    if (request == null || request.choices.isEmpty) return;
    final String id = request.choices[choice.index].id;
    final WorkspaceInfo? info = _app.get<WorkspaceInfo>('projectInfo');
    if (info == null || info.worktreeId != id) {
      transcript.add(TuiRole.system, '先 Enter 打开该项目，再按 r 重命名。');
      return;
    }
    final ProjectRecord? project = _app
        .get<ProjectRegistry>('projectRegistry')
        ?.project(info.projectId);
    choice.cancel();
    prefillInput('/project rename ${project?.name ?? info.projectName}');
  }

  Future<void> _handleWorktree(String arg) async {
    final WorktreeService? service = _app.get<WorktreeService>(
      'worktreeService',
    );
    if (service == null) {
      transcript.add(TuiRole.system, '项目注册表未启用，worktree 不可用。');
      return;
    }
    final String rest = arg.trim();
    if (rest.isEmpty || rest == 'list') {
      final List<WorkspaceInfo> list = service.list();
      if (list.isEmpty) {
        transcript.add(TuiRole.system, '没有已登记 worktree。');
        return;
      }
      final String current =
          _app.get<WorkspaceInfo>('projectInfo')?.worktreeId ?? '';
      final StringBuffer buffer = StringBuffer('worktree：');
      for (final WorkspaceInfo item in list) {
        final String mark = item.worktreeId == current ? '*' : ' ';
        buffer.write(
          '\n$mark ${item.worktreePath.split(Platform.pathSeparator).last}  '
          '${item.strategy ?? 'user'}  ${item.worktreePath}',
        );
      }
      transcript.add(TuiRole.system, buffer.toString());
      return;
    }
    if (rest == 'new' || rest.startsWith('new ')) {
      final List<String> parts = rest.substring(3).trim().split(RegExp(r'\s+'));
      final bool openAfter = parts.remove('--open');
      if (parts.isEmpty || parts.first.isEmpty) {
        transcript.add(
          TuiRole.system,
          '用法：/worktree new <名字> [branch] [--open]',
        );
        return;
      }
      try {
        final WorktreeCreateResult result = await service.create(
          parts.first,
          branch: parts.length > 1 ? parts[1] : null,
        );
        transcript.add(
          TuiRole.system,
          '已创建 worktree：${result.path}（分支 ${result.branch}）；'
          '用 /project open ${result.info.worktreeId.substring(0, 8)} 切换。',
        );
        if (openAfter) {
          final void Function(String)? callback = onSwitchProject;
          if (callback == null) {
            transcript.add(TuiRole.system, '当前模式不支持自动切换。');
          } else {
            callback(result.info.worktreePath);
          }
        }
      } catch (error) {
        transcript.add(TuiRole.system, '创建 worktree 失败：$error');
      }
      return;
    }
    if (rest == 'remove' || rest.startsWith('remove ')) {
      final List<String> parts = rest.substring(6).trim().split(RegExp(r'\s+'));
      final bool purge = parts.remove('--purge');
      final String selector = parts.join(' ').trim();
      if (selector.isEmpty) {
        transcript.add(TuiRole.system, '用法：/worktree remove <名字> --purge');
        return;
      }
      if (!purge) {
        transcript.add(
          TuiRole.system,
          '删除会同时删除数据目录；请用 /worktree remove <名字> --purge 确认。',
        );
        return;
      }
      try {
        await service.remove(selector, purge: true);
        transcript.add(TuiRole.system, '已删除 worktree：$selector');
      } catch (error) {
        transcript.add(TuiRole.system, '删除 worktree 失败：$error');
      }
      return;
    }
    transcript.add(
      TuiRole.system,
      '用法：/worktree [new <名字> [branch] [--open]|list|remove <名字> --purge]',
    );
  }

  Future<void> _handleLsp(String arg) async {
    final LspManager? manager = _app.get<LspManager>('lsp');
    if (manager == null) {
      transcript.add(TuiRole.system, 'LSP 未启用（[lsp] enabled = true 后重启 nava）。');
      return;
    }
    final String rest = arg.trim();
    if (rest == 'restart' || rest.startsWith('restart ')) {
      final String name = rest.substring('restart'.length).trim();
      await manager.restart(name.isEmpty ? null : name);
      transcript.add(
        TuiRole.system,
        name.isEmpty ? 'LSP 服务器已重启。' : 'LSP 服务器 $name 已重启。',
      );
      return;
    }
    final List<LspServerStatus> statuses = manager.statuses();
    if (statuses.isEmpty) {
      transcript.add(TuiRole.system, 'LSP 已启用，但没有配置服务器。');
      return;
    }
    final StringBuffer buffer = StringBuffer('LSP 服务器：');
    for (final LspServerStatus status in statuses) {
      buffer.write(
        '\n${status.name}  ${status.state}  '
        'diagnostics=${status.diagnosticCount}  '
        'capabilities=${status.capabilities.join(',')}',
      );
      if (status.error != null) buffer.write('  ${status.error}');
    }
    transcript.add(TuiRole.system, buffer.toString());
  }

  /// 项目数据目录：`workdir` 服务在时由它与 `project_dir` 推出。
  String _projectDataDir() {
    final String? resolved = _app.get<String>('projectDataDir');
    if (resolved != null) return resolved;
    final String? workdir = _app.get<String>('workdir');
    if (workdir == null) {
      return resolveConfigDir();
    }
    return resolveProjectDataDir(
      workdir: workdir,
      projectDir: _app.get<String>('projectDir'),
    );
  }

  /// `/cost`：今日成本、token 用量与当前模型的费率来源。
  ///
  /// 费率来自 models.dev（非计费口径）。查不到时**明说「费率未知」**而不是
  /// 报一个数——此前用的是两条写死的常数，对 DeepSeek 差一个量级、对 Gemini
  /// 差得更多，而用户没有任何办法看出那个数字是编的。
  void _showCost() {
    final CostTracker? tracker = _app.get<CostTracker>('costTracker');
    if (tracker is! CostTrackerImpl) {
      transcript.add(TuiRole.system, '成本追踪不可用。');
      return;
    }
    transcript.add(TuiRole.system, _costReport(tracker));
  }

  /// `/cost` 正文。
  String _costReport(CostTrackerImpl tracker) {
    final StringBuffer buffer = StringBuffer();
    if (tracker.hasRealUsage) {
      buffer.write('今日成本：\$${tracker.todayCost.toStringAsFixed(4)}');
    } else {
      buffer.write('尚无用量记录（跑一轮后才有数）');
    }
    buffer.write(
      '\n输入 ${tracker.promptTokens} / 输出 ${tracker.completionTokens}',
    );
    if (tracker.cachedTokens > 0) {
      buffer.write('（其中 ${tracker.cachedTokens} 命中缓存）');
    }
    buffer.write(' token，共 ${tracker.calls} 次调用');
    buffer.write('\n费率：${tracker.profile?.rateSummary ?? '未知'}');
    if (!tracker.ratesKnown && tracker.hasRealUsage) {
      buffer.write('—— models.dev 无该模型记录，成本按 0 计');
    }
    return buffer.toString();
  }

  /// `/rewind [N]`：回滚 N 轮（缺省 1）——工作区文件 + 对话都回到该轮之前。
  /// `/rewind list` 列出本会话可用检查点。对话回滚用 `Session.fork`（append-only
  /// 不变式，非破坏派生）+ `SessionStore.adopt` 注册，再切到 fork 会话。
  Future<void> _handleRewind(String arg) async {
    final CheckpointManager? checkpoint = _app.get<CheckpointManager>(
      'checkpointManager',
    );
    if (checkpoint == null || !checkpoint.enabled) {
      transcript.add(
        TuiRole.system,
        '检查点不可用：未装配或 [checkpoint] enabled = false。',
      );
      return;
    }
    if (busy) {
      transcript.add(TuiRole.system, '有在途轮次，请稍候再试。');
      return;
    }
    // `/rewind` 是一次性回滚：旧的 `/undo` 撤销点已不再描述工作区，留着只会
    // 让 `/redo` 把文件恢复到一个从未存在过的混合状态。
    _revertStage = null;
    _prefill = null;
    // 基线还在写：此时回滚没有可回滚的锚点，等它落盘（与首轮同一道门闩）。
    await _checkpointBase;
    final String command = arg.trim();
    if (command == 'list') {
      _showCheckpoints(checkpoint);
      return;
    }
    final int steps = int.tryParse(command) ?? 1;
    final Session? session = _session;
    try {
      final CheckpointRewindResult? result = await checkpoint.rewind(steps);
      if (result == null) {
        transcript.add(TuiRole.system, '没有可回滚的检查点。');
        return;
      }
      final String counts =
          '恢复 ${result.restore.restored}、'
          '删除 ${result.restore.deleted} 个文件';
      if (session == null) {
        transcript.add(TuiRole.system, '已回滚工作区到第 ${result.turn} 轮（$counts）。');
        return;
      }
      await _switchToRewind(result, session, counts);
    } catch (error) {
      transcript.add(TuiRole.system, '回滚失败：$error');
    }
  }

  /// 对话回滚：从目标检查点的切点事件 fork 新会话（`lastEventId` 为 null 时
  /// 是空会话的 turn 0，直接建全新空会话），adopt 进仓库后切过去。
  ///
  /// 旧会话保留为记录（append-only 不变式）；切会话时 `_bind` 会为新会话写
  /// turn 0 快照，捕捉回滚后的文件状态。
  Future<void> _switchToRewind(
    CheckpointRewindResult result,
    Session session,
    String counts,
  ) async {
    final String? cut = result.lastEventId;
    final String forkId;
    if (cut == null) {
      forkId = _sessions.create().id;
    } else {
      final Session fork = session.fork(
        fromEventId: cut,
        id: 'session_${newUuidV4()}',
      );
      _sessions.adopt(fork);
      forkId = fork.id;
    }
    await switchSession(
      forkId,
      announce:
          '已回滚到第 ${result.turn} 轮（$counts，对话已回到该轮），'
          '新会话 $forkId。',
      system: true,
    );
  }

  void _showCheckpoints(CheckpointManager checkpoint) {
    final List<CheckpointInfo> infos = checkpoint.list();
    if (infos.isEmpty) {
      transcript.add(TuiRole.system, '没有可回滚的检查点。');
      return;
    }
    final StringBuffer buffer = StringBuffer('本会话检查点（${infos.length}）：');
    for (final CheckpointInfo info in infos) {
      buffer.write('\n  turn ${info.turn}：${info.files} 个文件');
    }
    transcript.add(TuiRole.system, buffer.toString());
  }

  /// `/background [list|output <id>|kill <id>]`：后台任务管理（不经模型）。
  Future<void> _handleBackground(String arg) async {
    final BackgroundTaskService? service = _app.get<BackgroundTaskService>(
      'backgroundTasks',
    );
    if (service == null) {
      transcript.add(TuiRole.system, '后台任务不可用：未装配。');
      return;
    }
    final int space = arg.indexOf(' ');
    final String sub = space < 0 ? arg.trim() : arg.substring(0, space).trim();
    final String rest = space < 0 ? '' : arg.substring(space + 1).trim();
    try {
      switch (sub) {
        case '' || 'list':
          _showBackgroundTasks(service);
        case 'output':
          if (rest.isEmpty) {
            transcript.add(TuiRole.system, kBackgroundUsage);
            return;
          }
          final String output = service.output(rest);
          transcript.add(
            TuiRole.system,
            '后台任务 $rest 输出：'
            '${output.isEmpty ? '（尚无输出）' : backgroundOutputTail(output)}',
          );
        case 'kill':
          if (rest.isEmpty) {
            transcript.add(TuiRole.system, kBackgroundUsage);
            return;
          }
          final bool killed = service.kill(rest);
          transcript.add(
            TuiRole.system,
            killed ? '已终止后台任务 $rest。' : '后台任务 $rest 已结束。',
          );
        default:
          transcript.add(TuiRole.system, kBackgroundUsage);
      }
    } on BackgroundException catch (error) {
      transcript.add(TuiRole.system, '后台任务操作失败：${error.message}');
    }
  }

  void _showBackgroundTasks(BackgroundTaskService service) {
    final List<BackgroundTaskView> tasks = service.list();
    if (tasks.isEmpty) {
      transcript.add(TuiRole.system, '当前没有后台任务。');
      return;
    }
    final StringBuffer buffer = StringBuffer('后台任务（${tasks.length}）：');
    for (final BackgroundTaskView task in tasks) {
      buffer.write(
        '\n  ${task.id} [${task.status.name}] ${task.command}'
        '（${task.elapsedMs}ms，输出 ${task.outputBytes}B）',
      );
    }
    transcript.add(TuiRole.system, buffer.toString());
  }

  /// `/doctor`：聚合体检（不经模型，只读）。
  void _showDoctor() {
    final List<DoctorCheck> checks = doctorChecks(_app);
    final StringBuffer buffer = StringBuffer('nava 体检：');
    int failed = 0;
    for (final DoctorCheck check in checks) {
      final String mark = switch ((check.ok, check.warning)) {
        (true, _) => '✓',
        (false, true) => '⚠',
        _ => '✗',
      };
      if (!check.ok && !check.warning) failed++;
      buffer
        ..write('\n  $mark ${check.name}')
        ..write(check.hint == null ? '' : ' — ${check.hint}');
    }
    buffer.write('\n${failed == 0 ? '未发现阻塞项。' : '发现 $failed 个需处理项（见上）。'}');
    transcript.add(TuiRole.system, buffer.toString());
  }

  /// `/story`：补丁时间轴与游标操作（不经模型，只读 `'doc'` 服务 +
  /// `'storyPending'`）。子命令：preview / discard / fork / pending / apply。
  Future<void> _handleStory(String arg) async {
    if (!storyEnabled) {
      transcript.add(
        TuiRole.system,
        '故事层未启用：在 config.toml 设 [story] enabled = true 后重启。',
      );
      return;
    }
    final DocEngine? engine = _sessionCtx?.get<DocEngine>('doc');
    if (engine == null) {
      transcript.add(TuiRole.system, '故事层不可用：会话未装配 doc 服务。');
      return;
    }
    final int space = arg.indexOf(' ');
    final String sub = space < 0 ? arg.trim() : arg.substring(0, space).trim();
    final String rest = space < 0 ? '' : arg.substring(space + 1).trim();
    try {
      await _runStorySub(engine, sub, rest);
    } on Object catch (error) {
      // 文件 / 会话日志 IO 失败不能变成未处理的异步异常。
      transcript.add(TuiRole.system, '故事操作失败：$error');
    }
  }

  Future<void> _runStorySub(DocEngine engine, String sub, String rest) async {
    switch (sub) {
      case '':
        transcript.add(TuiRole.system, renderStoryTimeline(engine.log.patches));
      case 'preview':
        _previewStory(engine, rest);
      case 'discard':
        await _discardStory(engine, rest);
      case 'fork':
        await _forkStory(engine, rest);
      case 'pending':
        final StoryPending? pending = _storyPending();
        transcript.add(
          TuiRole.system,
          renderStoryPending(
            pending?.patches ?? const <DocPatch>[],
            sources: pending?.sources ?? const <String, String>{},
          ),
        );
      case 'apply':
        await _applyStoryPending(engine, rest);
      case 'reject':
        _rejectStoryPending(rest);
      default:
        transcript.add(TuiRole.system, kStoryUsage);
    }
  }

  StoryPending? _storyPending() =>
      _sessionCtx?.get<StoryPending>('storyPending');

  /// `/story preview <n>`：预览前 n 个补丁时刻的文档状态。
  void _previewStory(DocEngine engine, String rest) {
    final int? n = int.tryParse(rest);
    if (n == null || n < 0 || n > engine.log.length) {
      transcript.add(TuiRole.system, kStoryUsage);
      return;
    }
    transcript.add(TuiRole.system, renderStoryPreview(engine.previewAt(n)));
  }

  /// `/story discard <n>`：驳回第 n 个补丁并把触及文件写回 fold 后内容。
  Future<void> _discardStory(DocEngine engine, String rest) async {
    final int? n = int.tryParse(rest);
    try {
      final StoryDiscardResult result = await discardStoryPatch(
        engine,
        _app.get<FileSystem>('fs'),
        n ?? -1,
      );
      transcript.add(TuiRole.system, renderStoryDiscard(result));
    } on ArgumentError catch (error) {
      transcript.add(TuiRole.system, '${error.message}');
    }
  }

  /// `/story fork <n>`：从前 n 个补丁分叉新会话并切过去（会话层 fork 已
  /// 接线：SessionLog.fork 复制前缀，切过去后 provideStory rebuild 自然
  /// 拿到分支历史）。
  Future<void> _forkStory(DocEngine engine, String rest) async {
    final int? n = int.tryParse(rest);
    if (busy || n == null || n < 1 || n > engine.log.length) {
      transcript.add(TuiRole.system, busy ? '有在途轮次，请稍候再试。' : kStoryUsage);
      return;
    }
    if (_app.get<SessionLog>('sessionLog') == null) {
      transcript.add(TuiRole.system, '故事层未持久化（无 sessionLog），无法分叉。');
      return;
    }
    final String forkId = 'session_${newUuidV4()}';
    await engine.forkAt(n, newSessionId: forkId);
    await switchSession(
      forkId,
      announce: '已从前 $n 个补丁分叉新故事线，新会话 $forkId。',
      system: true,
    );
  }

  /// `/story apply <i>`：应用第 i 个待应用补丁（经 fs 缝写文件后入故事）。
  Future<void> _applyStoryPending(DocEngine engine, String rest) async {
    final StoryPending? pending = _storyPending();
    if (pending == null) {
      transcript.add(TuiRole.system, '待应用通道不可用：会话未装配。');
      return;
    }
    final String text = await pending.apply(
      int.tryParse(rest) ?? -1,
      engine,
      _app.get<FileSystem>('fs'),
    );
    transcript.add(TuiRole.system, text);
  }

  /// `/story reject <i>`：丢弃第 i 个待定补丁（不落盘，文件未改动）。
  void _rejectStoryPending(String rest) {
    final StoryPending? pending = _storyPending();
    if (pending == null) {
      transcript.add(TuiRole.system, '待应用通道不可用：会话未装配。');
      return;
    }
    transcript.add(TuiRole.system, pending.reject(int.tryParse(rest) ?? -1));
  }

  /// `/goal [子命令]`：管理当前会话的长期目标（不经模型，直接调 Goal 服务）。
  Future<void> _handleGoal(String arg) async {
    final GoalService? goal = _goal;
    if (goal == null) {
      transcript.add(TuiRole.system, 'Goal 不可用：会话尚未绑定。');
      return;
    }
    final int space = arg.indexOf(' ');
    final String sub = space < 0 ? arg.trim() : arg.substring(0, space).trim();
    final String rest = space < 0 ? '' : arg.substring(space + 1).trim();
    try {
      await _runGoalSub(goal, sub, rest);
    } on GoalException catch (e) {
      transcript.add(TuiRole.system, '目标操作失败：${e.message}');
    }
  }

  /// `/commit`：提交流程——模型查看暂存 diff、写 Conventional Commits 提交
  /// 信息并经 `git_commit` 工具提交（high 风险走审批）。
  Future<void> _handleCommit() async {
    await submit(
      '执行提交流程：\n'
      '1. 先用 git_status 看有哪些未暂存的改动；'
      '若还有未暂存的，用 git_add 暂存（all=true 暂存全部，'
      '或按 paths 列出要暂存的路径）。\n'
      '2. 用 git_diff --staged 查看已暂存的改动。\n'
      '3. 基于改动写一条 Conventional Commits 提交信息（scope + 中文描述），'
      '用 git_commit 工具提交。',
    );
  }

  /// `/review`：审查当前未提交改动（提交/提 PR 前自检，只审不改）。
  Future<void> _handleReview() async {
    await submit(
      '审查当前未提交改动：用 git_diff 查看未暂存与暂存的全部差异，'
      '从命名、边界条件、安全隐患、性能四个方面给出结构化发现清单；'
      '**只审不改**，不要直接修改代码。若没有未提交改动，直接说明。',
    );
  }

  /// `/init`：让模型扫描仓库并生成 / 更新 AGENTS.md。
  ///
  /// 不直接写文件：提交固定提示词走正常轮次，由模型经 write 落盘
  /// （沙箱限定工作区、审批照常）。
  /// `/init` 生成的 AGENTS.md 章节骨架。
  ///
  /// 「诊断与自检命令」是刻意加的一节：把校验命令写进项目指令，让模型**交付前**
  /// 主动跑一遍。与 [LinterService] 的编辑后自动 lint 不重复——那管「刚改完有没有
  /// 弄坏」，这管「整体过不过得去」，两者时间尺度不同。
  static const String kInitSections = '项目概述、构建与测试命令、代码风格约定、诊断与自检命令、边界与注意事项';

  /// 诊断一节的写法约束：命令要来自仓库自身，别让模型凭空编。
  static const String kInitDiagnosticsHint =
      '「诊断与自检命令」一节要写明本项目改动交付前该跑的确切校验命令'
      '（类型检查 / lint），并要求每次交付前先跑一遍确认没有新增错误。'
      '命令以仓库自身的脚本与 CI 配置为准，按实际技术栈选，不要凭空编。';

  Future<void> _handleInit() async {
    final String? workdir = _app.get<String>('workdir');
    final bool exists =
        workdir != null &&
        File('$workdir${Platform.pathSeparator}AGENTS.md').existsSync();
    if (exists) {
      transcript.add(TuiRole.system, 'AGENTS.md 已存在，将让模型先读取再更新。');
    }
    await submit(
      '扫描当前仓库（工作目录）的结构与关键文件，生成 AGENTS.md：'
      '$kInitSections。$kInitDiagnosticsHint'
      '${exists ? '文件已存在：先读取再改写，保留仍有用的内容。' : '文件不存在：用 write 创建到仓库根。'}',
    );
  }

  Future<void> _runGoalSub(GoalService goal, String sub, String rest) async {
    switch (sub) {
      case '' || 'status':
        final Goal? current = goal.current;
        transcript.add(
          TuiRole.system,
          current == null
              ? '当前没有目标。用 /goal set <文本> 创建。'
              : _goalStatusText(current),
        );
      case 'set':
        if (rest.isEmpty) {
          transcript.add(TuiRole.system, kGoalUsage);
          return;
        }
        final Goal created = await goal.create(rest);
        transcript.add(TuiRole.system, '已创建目标：${created.text}');
      case 'edit':
        if (rest.isEmpty) {
          transcript.add(TuiRole.system, kGoalUsage);
          return;
        }
        final Goal edited = await goal.edit(rest);
        transcript.add(TuiRole.system, '目标已更新：${edited.text}');
      case 'pause':
        await goal.pause();
        transcript.add(TuiRole.system, '目标已暂停。');
      case 'resume':
        await goal.resume();
        transcript.add(TuiRole.system, '目标已恢复推进。');
      case 'done':
        await goal.complete();
        transcript.add(TuiRole.system, '目标已完成。');
      case 'clear':
        await goal.clear();
        transcript.add(TuiRole.system, '目标已清除。');
      default:
        transcript.add(TuiRole.system, kGoalUsage);
    }
  }

  String _goalStatusText(Goal goal) {
    final StringBuffer buffer = StringBuffer()
      ..write('当前目标：${goal.text}\n状态：${goal.status.name}')
      ..write('｜轮次：${goal.round} / ${goal.maxRounds}');
    if (goal.blockReason != null) {
      buffer.write('\n阻塞原因：${goal.blockReason}');
    }
    return buffer.toString();
  }

  /// `/cron [子命令]`：不经模型直接管理定时任务。
  Future<void> _handleCron(String arg) async {
    final CronService? cron = _app.get<CronService>('cron');
    if (cron == null) {
      transcript.add(TuiRole.system, '定时任务不可用：未装配 cron 服务。');
      return;
    }
    final int space = arg.indexOf(' ');
    final String sub = space < 0 ? arg.trim() : arg.substring(0, space).trim();
    final String rest = space < 0 ? '' : arg.substring(space + 1).trim();
    try {
      await _runCronSub(cron, sub, rest);
    } on CronException catch (e) {
      transcript.add(TuiRole.system, '定时任务操作失败：${e.message}');
    }
  }

  Future<void> _runCronSub(CronService cron, String sub, String rest) async {
    switch (sub) {
      case '' || 'list':
        _showCronTasks(cron);
      case 'add':
        _cronAdd(cron, rest);
      case 'remove':
        _cronRemove(cron, rest);
      case 'enable':
        _cronSetEnabled(cron, rest, enabled: true);
      case 'disable':
        _cronSetEnabled(cron, rest, enabled: false);
      case 'history':
        _showCronHistory(cron, rest);
      default:
        transcript.add(TuiRole.system, kCronUsage);
    }
  }

  void _cronAdd(CronService cron, String rest) {
    final Map<String, Object?>? input = _parseCronAdd(rest);
    if (input == null) {
      transcript.add(TuiRole.system, kCronUsage);
      return;
    }
    final CronTaskView view = cron.addDynamicTask(
      input,
      callerSessionId: _sessionId,
    );
    transcript.add(TuiRole.system, '已添加定时任务 ${view.id}。');
  }

  /// 解析 `/cron add` 的 `<内容> <at|every|daily|cron> <规则>`；形状不符返回 null。
  ///
  /// 规则在末尾：`at` / `every` / `daily` 各 1 个 token，`cron` 表达式 5 个 token
  /// （含空格），内容可含任意空格。规则词接受中文别名：`每天` / `每日` / `每隔` /
  /// `每周X`；`every` 间隔可带单位（10分钟 / 1小时）。
  Map<String, Object?>? _parseCronAdd(String rest) {
    final List<String> parts = rest
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.length < 3) return null;
    if (parts.length >= 7 && parts[parts.length - 6] == 'cron') {
      return <String, Object?>{
        'prompt': parts.sublist(0, parts.length - 6).join(' '),
        'cron': parts.sublist(parts.length - 5).join(' '),
      };
    }
    // `every 10 分钟`：数字与单位分空格，合并尾部两 token。
    if (parts.length >= 4 && _isEvery(parts[parts.length - 3])) {
      final num? seconds = _parseInterval(
        '${parts[parts.length - 2]} ${parts[parts.length - 1]}',
      );
      if (seconds != null) {
        return <String, Object?>{
          'prompt': parts.sublist(0, parts.length - 3).join(' '),
          'every': seconds,
        };
      }
    }
    final String prompt = parts.sublist(0, parts.length - 2).join(' ');
    final String kind = parts[parts.length - 2];
    final String value = parts[parts.length - 1];
    final String? weekday = _weeklyWeekday(kind);
    if (weekday != null) {
      final String? cron = _dailyCron(value, weekday);
      return cron == null
          ? null
          : <String, Object?>{'prompt': prompt, 'cron': cron};
    }
    return switch (kind) {
      'at' => <String, Object?>{'prompt': prompt, 'at': value},
      'daily' ||
      '每天' ||
      '每日' => <String, Object?>{'prompt': prompt, 'daily': value},
      'every' || '每隔' => _parseEvery(prompt, value),
      _ => null,
    };
  }

  bool _isEvery(String kind) => kind == 'every' || kind == '每隔';

  /// 间隔文本 → 秒；纯秒数或「数字 + 单位」。
  num? _parseInterval(String raw) {
    final String text = raw.trim().toLowerCase();
    if (text.isEmpty) return null;
    final num? plain = num.tryParse(text);
    if (plain != null) return plain;
    final RegExpMatch? match = RegExp(
      r'^(\d+(?:\.\d+)?)\s*(秒|s|分钟|分|min|mins|m|小时|时|h|hour|hours)$',
    ).firstMatch(text);
    if (match == null) return null;
    final double value = double.parse(match[1]!);
    return switch (match[2]!) {
      '秒' || 's' => value,
      '分钟' || '分' || 'min' || 'mins' || 'm' => value * 60,
      '小时' || '时' || 'h' || 'hour' || 'hours' => value * 3600,
      _ => null,
    };
  }

  Map<String, Object?>? _parseEvery(String prompt, String value) {
    final num? seconds = _parseInterval(value);
    if (seconds == null) return null;
    return <String, Object?>{'prompt': prompt, 'every': seconds};
  }

  /// `每周X` → cron 星期数（'1'-'6' 周一~六，'0' 周日）；非每周X 返回 null。
  String? _weeklyWeekday(String kind) {
    final RegExpMatch? match = RegExp(r'^每周([一二三四五六日天])$').firstMatch(kind);
    if (match == null) return null;
    return switch (match.group(1)!) {
      '一' => '1',
      '二' => '2',
      '三' => '3',
      '四' => '4',
      '五' => '5',
      '六' => '6',
      _ => '0',
    };
  }

  /// `HH:MM` + cron 星期数 → cron 表达式 `分 时 * * 星期`。
  String? _dailyCron(String value, String weekday) {
    final RegExpMatch? match = kCronDailyPattern.firstMatch(value);
    if (match == null) return null;
    return '${int.parse(match[2]!)} ${int.parse(match[1]!)} * * $weekday';
  }

  void _cronRemove(CronService cron, String id) {
    if (id.isEmpty) {
      transcript.add(TuiRole.system, kCronUsage);
      return;
    }
    cron.removeDynamicTask(id);
    transcript.add(TuiRole.system, '已删除定时任务 $id。');
  }

  void _cronSetEnabled(CronService cron, String id, {required bool enabled}) {
    if (id.isEmpty) {
      transcript.add(TuiRole.system, kCronUsage);
      return;
    }
    final CronTaskView view = cron.setEnabled(id, enabled);
    transcript.add(TuiRole.system, '已${enabled ? '启用' : '停用'}定时任务 ${view.id}。');
  }

  void _showCronTasks(CronService cron) {
    final List<CronTaskView> tasks = cron.listTasks();
    if (tasks.isEmpty) {
      transcript.add(TuiRole.system, '当前没有定时任务。');
      return;
    }
    final StringBuffer buffer = StringBuffer('定时任务（${tasks.length}）：');
    for (final CronTaskView view in tasks) {
      buffer
        ..write(
          '\n  ${view.id} [${view.enabled ? '启用' : '停用'}] '
          '${_cronScheduleText(view)}',
        )
        ..write(
          view.nextRunAt == null ? '' : ' 下次=${_formatLocal(view.nextRunAt!)}',
        )
        ..write(' 内容=${view.prompt}');
    }
    transcript.add(TuiRole.system, buffer.toString());
  }

  String _cronScheduleText(CronTaskView view) {
    final MapEntry<String, Object?> entry = view.schedule.entries.first;
    final String value = '${entry.value}';
    return switch (entry.key) {
      'at' => 'at $value',
      'everySeconds' => 'every ${value}s',
      'daily' => 'daily $value',
      _ => 'cron $value',
    };
  }

  void _showCronHistory(CronService cron, String rest) {
    final int? limit = int.tryParse(rest);
    final List<CronRunRecord> records = cron.listHistory(limit: limit ?? 10);
    if (records.isEmpty) {
      transcript.add(TuiRole.system, '尚无定时任务运行记录。');
      return;
    }
    final StringBuffer buffer = StringBuffer('运行记录（最新在前）：');
    for (final CronRunRecord record in records) {
      buffer
        ..write(
          '\n  #${record.seq} ${record.taskId} '
          '${_cronStatusText(record.status)} 排期=${_formatLocal(record.scheduledFor)}',
        )
        ..write(record.excerpt == null ? '' : ' 结果=${record.excerpt}');
    }
    transcript.add(TuiRole.system, buffer.toString());
  }

  String _cronStatusText(String status) => switch (status) {
    CronRunStatus.completed => '完成',
    CronRunStatus.failed => '失败',
    CronRunStatus.delivered => '已交付',
    _ => status,
  };

  /// 本地时区的 `yyyy-MM-dd HH:mm` 展示。
  String _formatLocal(DateTime instant) {
    final DateTime local = instant.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /// `/remember <内容>`：直接调用记忆能力，绕过模型。
  Future<void> _remember(String arg) async {
    final MemoryStore? memory = _app.get<MemoryStore>('memory');
    if (memory == null) {
      transcript.add(TuiRole.system, '记忆服务不可用。');
      return;
    }
    final String text = arg.trim();
    if (text.isEmpty) {
      transcript.add(TuiRole.system, '用法：/remember <要记住的内容>');
      return;
    }
    final MemoryEntry entry = await memory.remember(text, tags: {'explicit'});
    transcript.add(TuiRole.system, '已记住（id=${entry.id}）。');
  }

  /// `/forget <id 或 关键字>`：直接调用遗忘能力，绕过模型。
  Future<void> _forget(String arg) async {
    final MemoryStore? memory = _app.get<MemoryStore>('memory');
    if (memory == null) {
      transcript.add(TuiRole.system, '记忆服务不可用。');
      return;
    }
    final String query = arg.trim();
    if (query.isEmpty) {
      transcript.add(TuiRole.system, '用法：/forget <id 或 关键字>');
      return;
    }
    if (await memory.forget(query)) {
      transcript.add(TuiRole.system, '已遗忘 id="$query"。');
      return;
    }
    final int deleted = await memory.forgetMatching(query);
    if (deleted == 0) {
      transcript.add(TuiRole.system, '未找到匹配 "$query" 的记忆。');
      return;
    }
    transcript.add(TuiRole.system, '已遗忘 $deleted 条匹配 "$query" 的记忆。');
  }

  void _showTelemetry() {
    final Telemetry? telemetry = _app.get<Telemetry>('telemetry');
    if (telemetry is! InMemoryTelemetry) {
      transcript.add(TuiRole.system, '遥测服务不可用。');
      return;
    }
    final List<TelemetryEvent> recent = telemetry.recent;
    if (recent.isEmpty) {
      transcript.add(TuiRole.system, '尚无遥测事件。');
      return;
    }
    final Iterable<String> names = recent
        .skip(recent.length > 8 ? recent.length - 8 : 0)
        .map((TelemetryEvent event) => event.name);
    transcript.add(TuiRole.system, '最近遥测：${names.join('、')}');
  }

  /// `/team [status|interrupt <id>]`：团队状态摘要与成员管理（不经模型）。
  Future<void> _handleTeam(String arg) async {
    final AgentTeam? team = _sessionCtx?.get<AgentTeam>('team');
    if (team == null) {
      transcript.add(TuiRole.system, '团队不可用：会话尚未装配团队服务。');
      return;
    }
    final int space = arg.indexOf(' ');
    final String sub = space < 0 ? arg.trim() : arg.substring(0, space).trim();
    final String rest = space < 0 ? '' : arg.substring(space + 1).trim();
    try {
      switch (sub) {
        case '':
          // 无参进入团队视图（Esc 返回对话）。
          onOpenTeamView?.call();
        case 'status':
          transcript.add(TuiRole.system, summarizeTeamProgress(teamSnapshot));
        case 'interrupt':
          if (rest.isEmpty) {
            transcript.add(TuiRole.system, kTeamUsage);
            return;
          }
          await team.interrupt(rest);
          transcript.add(TuiRole.system, '已中断成员 $rest。');
        default:
          transcript.add(TuiRole.system, kTeamUsage);
      }
    } on TeamException catch (e) {
      transcript.add(TuiRole.system, '团队操作失败：${e.message}');
    }
  }

  /// `/task [claim|release <id>]`：任务板手动干预（不经模型）。
  Future<void> _handleTask(String arg) async {
    final AgentTeam? team = _sessionCtx?.get<AgentTeam>('team');
    if (team == null) {
      transcript.add(TuiRole.system, '团队不可用：会话尚未装配团队服务。');
      return;
    }
    final int space = arg.indexOf(' ');
    final String sub = space < 0 ? arg.trim() : arg.substring(0, space).trim();
    final String rest = space < 0 ? '' : arg.substring(space + 1).trim();
    try {
      switch (sub) {
        case 'claim':
          if (rest.isEmpty) {
            transcript.add(TuiRole.system, kTaskUsage);
            return;
          }
          final TeamTask? task = team.task(rest);
          if (task == null) {
            transcript.add(TuiRole.system, '任务不存在：$rest');
            return;
          }
          await team.claimTask(rest, 'user');
          transcript.add(TuiRole.system, '已领取任务：${task.description}');
        case 'release':
          if (rest.isEmpty) {
            transcript.add(TuiRole.system, kTaskUsage);
            return;
          }
          await team.releaseTask(rest, 'user');
          transcript.add(TuiRole.system, '已释放任务 $rest。');
        default:
          transcript.add(TuiRole.system, kTaskUsage);
      }
    } on TeamException catch (e) {
      transcript.add(TuiRole.system, '任务操作失败：${e.message}');
    }
  }

  /// `/theme`：打开主题浮层，选中后立即应用（仅当前进程生效）。
  Future<void> _handleTheme() async {
    final String? name = await themePrompt.choose();
    if (name == null) {
      transcript.add(TuiRole.system, '已取消主题切换。');
      return;
    }
    setTheme(name);
    transcript.add(TuiRole.system, '已切换到「$name」主题。');
  }

  /// `/permission`：打开权限模式选择面板（不经模型）。
  ///
  /// 选中后经 [applyPermissionMode] 持久化到会话并更新作用域阈值；取消不切换。
  Future<void> _handlePermission() async {
    final TuiPermissionMode? mode = await permissionPrompt.choose(
      _permissionMode,
    );
    if (mode == null) {
      transcript.add(TuiRole.system, '已取消权限模式切换。');
      return;
    }
    if (mode == _permissionMode) {
      transcript.add(TuiRole.system, '已处于「${mode.label}」权限模式。');
      return;
    }
    applyPermissionMode(mode);
  }

  /// 展开 / 收起最近一条可折叠详情（工具结果 / 思考过程，ctrl+o；无可折叠
  /// 消息时不动作）。
  void toggleToolExpanded() {
    for (final TuiMessage message in transcript.messages.reversed) {
      if (message.role != TuiRole.tool && message.role != TuiRole.thinking) {
        continue;
      }
      // 跳过本来就不折叠的短消息：最近一条可折叠的才响应 ctrl+o。
      if (message.text.split('\n').length <= kToolPreviewLines) continue;
      message.expanded = !message.expanded;
      _refresh();
      return;
    }
  }

  /// 流式增量透传：思考 / 正文 delta 实时追加到屏上消息（同一条边到边增长），
  /// 终态结束本步流式。
  void _onLlmStream(LlmStreamEvent event) {
    if (_turnInterrupted) return;
    if (event is LlmReasoningDelta) {
      transcript.appendStream(reasoning: event.text);
      _refresh();
    } else if (event is LlmTextDelta) {
      transcript.appendStream(text: event.text);
      _refresh();
    } else if (event is LlmStreamDone) {
      transcript.endStream();
    }
  }

  /// 展开 / 收起 TODO 列表（ctrl+t；无计划时不动作）。
  void togglePlanExpanded() {
    final TuiMessage? message = transcript.planMessage;
    if (message == null) {
      return;
    }
    message.expanded = !message.expanded;
    _refresh();
  }

  Future<void> _bind(String id) async {
    final Session session = await _sessions.open(id);
    _session = session;
    // Agent 选择按会话恢复：标签之间互不继承（_firstBind 只用于启动会话）。
    // 自定义命令的临时覆盖优先于会话事件，回合结束后再还原。
    final String fallback = _firstBind ? _startupAgentId() : _defaultAgentId();
    _agentId = _bindAgentOverride ?? _sessionAgentId(session, fallback);
    // OpenCode 网关请求头按当前会话发送；其它 provider 忽略。
    _app.providers?.sessionId = session.id;
    final Context ctx = _app.plugin('tui-session:$id', (Context child) {
      provideAgentLoop(
        child,
        session: session,
        maxSteps: maxSteps,
        planning: planning,
        onStream: _onLlmStream,
      );
      // 计划闭环：todowrite 无计划时创建，有计划时在执行中推进。
      provideUpdatePlanTool(child, session: session);
      providePlanMode(child, session: session);
      provideGoal(child, session: session);
      // 自主运行：独立 Agent Loop（无 goalDriver）+ 根上下文的 costTracker。
      provideAutonomous(child, session: session, maxSteps: maxSteps);
      provideSessionSchedule(child, session: session, sessions: _sessions);
      provideScheduleTools(child);
      provideScheduleRuntime(child, deliver: _deliverReminder);
      provideAgentTeam(
        child,
        session: session,
        telemetry: _app.get<Telemetry>('telemetry'),
      );
      provideTeamTools(child);
      configureSession?.call(child, session);
    });
    _sessionCtx = ctx;
    if (storyEnabled) {
      await provideStory(ctx, sessionId: id, session: session, review: true);
    }
    _agent = ctx.agentLoop;
    _applyAgentPrompt();
    // 轮内注入：排队消息与人的编辑通报在模型组下一次请求前取走。
    _agent?.steering = _takeQueuedForSteering;
    _planMode = ctx.planMode;
    _goal = ctx.goal;
    // 权限模式按会话恢复：每个会话折叠自己的 permission/mode 后缀，
    // 同时清空审批门的「总是允许」清单（它也是会话级状态）。
    _gate?.resetAlwaysAllowed();
    _permissionMode = restorePermissionMode(
      session,
      fallback: initialPermissionMode,
    );
    // 会话规则初始为空；Agent 自带规则只收紧（allow 被丢弃并追加在末尾）。
    final PermissionWiring? wiring = _app.get<PermissionWiring>(
      'permissionWiring',
    );
    wiring?.setSessionRules(const <PermissionRule>[]);
    wiring?.setAgentRules(
      agentDefinition?.permissions ?? const <PermissionRule>[],
    );
    _syncPermissionMode();
    transcript.rebuildFrom(session);
    _eventSub = session.onEvent((SessionEvent event) {
      transcript.apply(event);
      _refresh();
    });
    final SessionUiStateStore? uiStore = _uiStore;
    _uiState = uiStore == null ? SessionUiState.empty : await uiStore.load(id);
    _resetHistoryNavigation();
    _pendingScroll = _uiState.scrollOffset;
    _bindTeam(ctx);
    // 检查点：绑定会话即接管已有时间线（无历史时写 turn 0 初始快照，供回滚
    // 到「全部轮次之前」）。同行重开时不抹掉旧轮次——redo / diff 要用。
    // 后台起拍、不挡就绪——大工作区的全量基线可达数十秒，挡在这里会让整个
    // 界面卡在「正在加载会话…」（而会话本身只有几 KB）。真正的门闩在
    // [submit]：第一轮开跑前等基线落定，避免快照飞行中被工具改出撕裂状态。
    _checkpointBase = _startCheckpoint(id, session.lastEventId);
    ready = true;
  }

  /// 后台起拍检查点：接管已有时间线（`--session` 恢复不抹历史），无历史时
  /// 写 turn 0 基线；错误说明补进 transcript（基线未就绪时 `/rewind` 不可用，
  /// 属降级不属阻塞）。
  Future<void> _startCheckpoint(String id, String? lastEventId) async {
    final CheckpointManager? checkpoint = _app.get<CheckpointManager>(
      'checkpointManager',
    );
    if (checkpoint == null) return;
    final String? error = await checkpoint.bind(id, lastEventId: lastEventId);
    if (error != null && ready) transcript.add(TuiRole.system, error);
  }

  /// 绑定团队订阅与语音播报（装配了团队服务时生效）。
  void _bindTeam(Context ctx) {
    final AgentTeam? team = ctx.get<AgentTeam>('team');
    if (team == null) return;
    _teamSub = TeamSubscription(
      team: team,
      onChanged: (TeamSnapshot _) => _refresh(),
      // 成员共用 costTracker，成本从根上下文取——此前这个 seam 从没被注入过，
      // 状态栏的成本位一直是 0。
      costSource: _CostBridge(_app.get<CostTrackerImpl>('costTracker')),
    );
    // 子 Agent 泳道：子 Agent 不在 AgentTeam 里，但视图层统一，故把它的活动
    // 直接写进同一张泳道表。名字由投影器维护。
    final SwarmProjection? swarm = _app.get<SwarmProjection>('swarmProjection');
    swarm?.sink.attach(
      (String laneId, String line, bool failed) => _teamSub?.addSwarmLine(
        laneId,
        line,
        failed: failed,
        label: swarm.labels[laneId] ?? '子 Agent',
      ),
    );
  }

  void _unbind() {
    _eventSub?.call();
    _eventSub = null;
    _teamSub?.dispose();
    _teamSub = null;
    _app.get<CheckpointManager>('checkpointManager')?.detach();
    // 换掉在飞门闩：基线仍会自己跑完（`detach` 已让它在链上让位），但下个
    // 会话的首轮不该等它。
    _checkpointBase = null;
    _queue.clear();
    _app.providers?.sessionId = null;
    _agentPromptDisposer?.call();
    _agentPromptDisposer = null;
    _sessionCtx?.dispose();
    _sessionCtx = null;
    _agent = null;
    _planMode = null;
    _goal = null;
    _session = null;
    ready = false;
  }

  Future<void> _afterTurn() async {
    await _sessions.flush();
    final RecoveryService? recovery = _app.get<RecoveryService>('recovery');
    final Session? session = _session;
    if (recovery != null && session != null && !session.closed) {
      try {
        await recovery.snapshot(session);
      } catch (error) {
        transcript.add(TuiRole.system, '快照保存失败：$error');
      }
    }
    // 轮次结束即空闲：让到期的提醒立刻交付，而不必等到下一次定时唤醒。
    _sessionCtx?.get<ScheduleRuntime>('scheduleRuntime')?.requestDrive();
    // 检查点：收口后快照本轮工作区（失败只提示不打断）。
    final CheckpointManager? checkpoint = _app.get<CheckpointManager>(
      'checkpointManager',
    );
    if (checkpoint != null) {
      final String? error = await checkpoint.recordTurn(
        lastEventId: _session?.lastEventId,
      );
      if (error != null) {
        transcript.add(TuiRole.system, error);
      }
    }
    // 自定义命令的 Agent / 模型覆盖只作用于这一轮：收口后先还原，再投递排队
    // 消息，避免覆盖泄漏到下一条输入。
    await _restoreTurnOverride();
    if (_definitionsDirty && !busy) {
      _definitionsDirty = false;
      await reloadDefinitions(announce: false);
    }
    // 消息队列：收口后投递下一条排队输入（一次一条，依次衔接）。
    // 多数时候队列已被 steering 取空（轮内注入），这里是兜底路径。
    if (_queue.isNotEmpty && !busy) {
      final (String, List<TuiAttachment>) next = _queue.removeAt(0);
      unawaited(submit(next.$1, attachments: next.$2));
    }
    // Stop hook：轮次收口（失败只提示）。
    final Hooks? hooks = _app.get<Hooks>('hooks');
    if (hooks != null) {
      final String? hookError = await hooks.onStop();
      if (hookError != null) {
        transcript.add(TuiRole.system, 'Stop hook 失败：$hookError');
      }
    }
  }

  /// SteeringSource：合并两个来源——先 storyNotices（人的编辑通报，先感知
  /// 世界变化），后排队消息文本；取走即清空。Agent Loop 在组下一次模型
  /// 请求前调用（轮内注入，不等轮末）。取出后刷新 UI（「已排队 n 条」
  /// 即时递减）；注入消息的附件 v1 丢弃（插话是纯文本）。
  Future<List<String>> _takeQueuedForSteering() async {
    final List<String> notices =
        _sessionCtx?.get<StoryNotices>('storyNotices')?.drain() ??
        const <String>[];
    // 只注入队首连续的纯文本消息：带附件的消息留给轮末 drain 原样投递，
    // 否则 steering 会把附件静默丢掉（附件不在注入通道的契约里）。
    int take = 0;
    while (take < _queue.length && _queue[take].$2.isEmpty) {
      take++;
    }
    final List<String> texts = <String>[
      for (final (String, List<TuiAttachment>) entry in _queue.take(take))
        entry.$1,
    ];
    if (notices.isEmpty && texts.isEmpty) return const <String>[];
    _queue.removeRange(0, take);
    _refresh();
    return <String>[...notices, ...texts];
  }

  /// 调度交付：空闲时把提醒当作一轮用户输入投递，返回是否成功入队。
  ///
  /// 忙时返回 `false`，调度器不会记录派发，记录保持活动并在下一次触发时重试。
  Future<bool> _deliverReminder(String text) async {
    if (busy || _agent == null) return false;
    unawaited(submit(text));
    return true;
  }

  /// 已入队、等待轮次收口回报状态的 cron 运行记录 id。
  final Set<String> _cronRuns = <String>{};

  /// cron 交付：空闲时把任务 framing 当作一轮用户输入投递，返回是否成功入队。
  ///
  /// 忙时返回 `false`，cron 运行时不写运行戳，下个 tick 重试；轮次收口时经
  /// [_settleCronRuns] 把执行结果回报给 cron 运行历史。
  Future<bool> deliverCron(String recordId, String framing) async {
    if (busy || _agent == null) return false;
    _cronRuns.add(recordId);
    unawaited(submit(framing));
    return true;
  }

  /// 轮次收口：把本轮结果回报给所有待收口的 cron 运行记录。
  void _settleCronRuns({required bool ok, required String reply}) {
    if (_cronRuns.isEmpty) return;
    final CronRuntime? runtime = _app.get<CronRuntime>('cronRuntime');
    final String excerpt = reply.trim();
    for (final String recordId in _cronRuns.toList()) {
      runtime?.finishRun(
        recordId,
        ok: ok,
        excerpt: excerpt.isEmpty ? null : excerpt,
      );
    }
    _cronRuns.clear();
  }

  void _refresh() => onChanged?.call();
}

/// 自定义命令的临时覆盖还原点。
class _TurnOverride {
  const _TurnOverride({
    required this.agentId,
    required this.entries,
    required this.modelLabel,
    required this.planModeActive,
  });

  /// 命令执行前的 Agent ID。
  final String agentId;

  /// 命令执行前的 LLM 链候选项（`provider/model`，首项为主）。
  final List<String> entries;

  /// 命令执行前的模型标签。
  final String modelLabel;

  /// 命令执行前 Plan Mode 是否激活（手动 `/plan` 也要原样还原）。
  final bool planModeActive;
}

/// 一组模型候选 + 展示标签。
class _ModelChoice {
  const _ModelChoice({required this.entries, required this.label});

  /// `provider/model` 候选（首项为主）。
  final List<String> entries;

  /// 状态栏标签。
  final String label;
}

/// 把 costTracker 适配成团队的 [TeamCostSource]。
///
/// 成员共用根上下文的 costTracker（子 Agent 也记进同一个），故团队总成本就是
/// 它累计的 `todayCost`——不再单开一套计费。此前这个 seam 从没被注入过，
/// 状态栏的成本位一直是 0。
class _CostBridge implements TeamCostSource {
  const _CostBridge(this._tracker);

  final CostTrackerImpl? _tracker;

  @override
  double get totalCost => _tracker?.todayCost ?? 0.0;
}

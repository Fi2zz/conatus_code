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
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:conatus_schedule/conatus_schedule.dart';
import 'package:conatus_skill/conatus_skill.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:conatus_tts/conatus_tts.dart';

import '../../providers.dart';
import '../autonomous/autonomous_assembly.dart';
import '../background/background_tasks.dart';
import '../budget/cost_tracker.dart';
import '../checkpoint/checkpoint_manager.dart';
import '../checkpoint/checkpoint_types.dart';
import '../config/config_writer.dart';
import '../tools/update_plan.dart';
import 'ask_user_tool.dart';
import 'at_ref.dart';
import 'team_snapshot.dart';
import 'team_subscription.dart';
import 'transcript.dart';
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
import 'tui_session_picker.dart';
import 'tui_skill_command.dart';
import 'voice_reporter.dart';

part 'tui_controller_provider.dart';

/// `/goal` 用法提示。
const String kGoalUsage =
    '用法：/goal [status|set <文本>|edit <文本>|pause|resume|done|clear]';

/// `/cron` 用法提示。
const String kCronUsage = '用法：/cron [list|add <内容> <at|every|daily|cron> <规则>|'
    'remove <id>|enable <id>|disable <id>|history [条数]]\n'
    '规则：at=ISO 时刻；every=秒或 10分钟/1小时；daily/每天=HH:MM；'
    '每周X=HH:MM；cron=5 段表达式';

/// `/team` 用法提示。
const String kTeamUsage =
    '用法：/team（进入团队视图）[status|interrupt <成员 id>]';

/// `/task` 用法提示。
const String kTaskUsage = '用法：/task [claim <任务 id>|release <任务 id>]';

/// `/background` 用法提示。
const String kBackgroundUsage =
    '用法：/background [list|output <任务 id>|kill <任务 id>]';

/// 消息队列容量上限（busy 时排队追问）。
const int kMessageQueueCap = 20;

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
    this.tts,
    this.ttsSink,
    this.initialPermissionMode = TuiPermissionMode.askWhenNeeded,
  })  : _app = app,
        _sessions = sessions,
        _sessionId = initialSession ?? '' {
    picker = TuiSessionPicker(sessions, onChanged: _refresh);
    _app.provide('tuiController', this);
    final TuiPermissionGate? gate = app.get<TuiPermissionGate>('approval');
    _gate = gate;
    choice.onChanged = _refresh;
    _syncPermissionMode();
  }

  final Context _app;
  final SessionStore _sessions;

  /// 选项浮层（`ask_user` 与工具审批共用）。
  ///
  /// 优先复用根上下文里已提供的 `'tuiChoice'`（审批门持有的是同一个），
  /// 未提供时自建一个。
  @override
  late final TuiChoicePrompt choice =
      _app.get<TuiChoicePrompt>('tuiChoice') ?? TuiChoicePrompt();

  late final TuiPermissionGate? _gate;

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

  /// 当前会话消息体量的粗估 token（chars/4 口径，只作状态栏展示）。
  int get contextTokens => estimateMessagesTokens(<LlmMessage>[
        for (final TuiMessage message in transcript.messages)
          LlmMessage(message.role.name, message.text),
      ]);

  /// Agent Loop 单轮最大步数。
  final int maxSteps;

  /// 会话是否先跑规划轮（`plan_write`）再执行；开启后每条新任务会先产出
  /// TODO 计划（屏上 `plan` 消息），执行过程从第一步可见。
  final bool planning;

  /// 退出请求（`/exit`、`/quit`、Ctrl+C）；由宿主接 `shutdownApp`。
  final void Function()? onExit;

  /// TTS 服务（可选）。注入后随会话装配团队语音播报。
  final TtsService? tts;

  /// TTS 音频输出目标（可选）。缺省 no-op，桌面 TUI 无声。
  final TtsAudioSink? ttsSink;

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

  /// `/team`（无参）进入团队视图的宿主回调；由根组件注入切换视图。
  void Function()? onOpenTeamView;

  /// provider 管理浮层（`/provider`，只读展示）。
  late final TuiProviderPrompt providerPrompt =
      TuiProviderPrompt(onChanged: _refresh);

  /// 模型选择浮层（`/model` 打开；搜索过滤，Enter 切换）。
  late final TuiModelPrompt modelPrompt = TuiModelPrompt(onChanged: _refresh);

  /// 权限模式选择浮层（`/permission` 打开；↑↓ 选择，Enter 切换）。
  late final TuiPermissionPrompt permissionPrompt =
      TuiPermissionPrompt(onChanged: _refresh);

  /// Plan Mode 面板浮层（`/plan`）。
  late final TuiPlanPrompt planPrompt = TuiPlanPrompt(onChanged: _refresh);

  /// 表单浮层。
  late final TuiFormPrompt formPrompt = TuiFormPrompt(onChanged: _refresh);

  /// 屏上记录。
  final Transcript transcript = Transcript();

  /// 会话选择面板。
  late final TuiSessionPicker picker;

  /// 状态变化通知（组件据此 `setState`）。
  void Function()? onChanged;

  String _sessionId;
  Session? _session;
  Context? _sessionCtx;
  AgentLoop? _agent;
  PlanMode? _planMode;
  GoalService? _goal;
  Disposer? _eventSub;

  /// 在飞轮次的取消句柄（Esc / 打断）；null = 无在飞轮次。
  AgentCancel? _cancel;

  /// 团队订阅（随会话绑定/解绑）。
  TeamSubscription? _teamSub;

  /// 团队语音播报（随会话绑定/解绑；tts 注入时启用）。
  VoiceReporter? _voice;

  /// 当前权限模式下挂着的审批中间件撤销句柄；Never Ask 时为 `null`。
  Disposer? _approvalGate;

  /// 当前权限模式（随绑定的会话变化）。
  TuiPermissionMode _permissionMode = TuiPermissionMode.askWhenNeeded;

  /// 是否有在途轮次。
  bool busy = false;

  /// 排队中的用户输入（busy 时入队，收口后依次投递；上限 [kMessageQueueCap]）。
  final List<(String, List<TuiAttachment>)> _queue =
      <(String, List<TuiAttachment>)>[];

  /// 排队消息条数。
  int get queuedCount => _queue.length;

  /// 会话是否已绑定就绪。
  bool ready = false;

  /// 当前会话 id。
  String get sessionId => _sessionId;

  /// 当前权限模式。
  @override
  TuiPermissionMode get permissionMode => _permissionMode;

  /// 状态栏展示的权限模式名。
  String get permissionLabel => _permissionMode.label;

  /// 团队状态快照（未装配团队或未绑定时为空）。
  TeamSnapshot get teamSnapshot => _teamSub?.snapshot ?? const TeamSnapshot();

  /// 切换权限模式：持久化到当前会话、按新阈值重挂审批中间件并提示。
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
    if (mode == _permissionMode && _approvalGate != null) {
      return;
    }
    _permissionMode = mode;
    session.append(kPermissionModeEvent, data: <String, Object?>{'mode': mode.name});
    _syncPermissionMode();
    transcript.add(TuiRole.system, '权限模式已切换为「${mode.label}」：${mode.description}');
    _refresh();
  }

  /// 按当前模式挂载 / 卸载审批中间件（幂等）。
  void _syncPermissionMode() {
    _approvalGate?.call();
    _approvalGate = null;
    final TuiPermissionGate? gate = _gate;
    final ToolRisk? threshold = _permissionMode.threshold;
    if (gate == null || threshold == null) {
      return;
    }
    _approvalGate = instrumentApproval(
      _app,
      approval: gate,
      threshold: threshold,
      timeout: kTuiDecisionTimeout,
    );
  }

  /// 绑定初始会话；未配置 provider 时自动打开引导面板。
  ///
  /// 未指定会话 id（构造时 `initialSession` 为 `null`）时，先经会话仓库新建
  /// 一个 `session_<uuid>` 会话再绑定，不会恢复历史会话。
  Future<void> start() async {
    if (_sessionId.isEmpty) {
      _sessionId = _sessions.create().id;
    }
    await _bind(_sessionId);
    _refresh();
    // 回填当前模型的上下文窗口（models.dev 缓存优先，失败保持未知）。
    unawaited(seedModelContextLength());
    if (_app.get<bool>('providerSetupNeeded') ?? false) {
      final ProviderRegistry? registry = _app.providers;
      if (registry != null) {
        providerPrompt.show(providerItems(registry));
      }
    }
  }

  /// 释放当前会话绑定（幂等）。
  void dispose() => _unbind();

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
    cancel.cancel();
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
    if (busy) {
      // busy 时排队追问（上限 [kMessageQueueCap]）；未绑定会话不排队。
      if (_agent == null) {
        transcript.add(TuiRole.system, '正在回复，请稍候（Esc 可打断）。');
        _refresh();
        return;
      }
      if (_queue.length >= kMessageQueueCap) {
        transcript.add(
          TuiRole.system,
          '排队已满（$kMessageQueueCap 条），请稍后再试。',
        );
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
      final AttachmentMaterialization? payload =
          await _materializeAttachments(attachments);
      if (payload == null) return;
      images = payload.images;
      messageText = payload.inlineText + text;
    }
    final AgentCancel cancel = AgentCancel();
    _cancel = cancel;
    busy = true;
    _refresh();
    bool turnOk = true;
    String reply = '';
    try {
      final AgentTurn turn =
          await agent.run(messageText, cancel: cancel, images: images);
      reply = turn.reply;
    } on AgentCancelled {
      turnOk = false;
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

  /// 确认选择：切到选中会话并关闭面板。
  Future<void> pickSelected() async {
    final String? id = picker.selectedId();
    picker.close();
    if (id != null) {
      await switchSession(id);
    }
  }

  /// 切换会话：不存在则懒建（各自文件与历史）；非法 id 只提示不切换。
  Future<void> switchSession(String id, {String? announce}) async {
    if (!isValidSessionId(id)) {
      transcript.add(TuiRole.system, '会话 id 非法：只允许字母/数字/下划线/中文/短横，长度 1—64。');
      _refresh();
      return;
    }
    if (ready && id == _sessionId) {
      transcript.add(TuiRole.system, '已在会话 $_sessionId。');
      _refresh();
      return;
    }
    _unbind();
    _sessionId = id;
    await _bind(id);
    transcript.add(
      TuiRole.system,
      announce ?? '已切换到会话 $_sessionId（数据文件：$_sessionId.jsonl）。',
    );
    _refresh();
  }

  /// 开启新会话。
  Future<void> newSession() async {
    final Session session = _sessions.create();
    await switchSession(
      session.id,
      announce: '已开启新会话 ${session.id}（上一会话已保存，/sessions 可切回）。',
    );
  }

  Future<void> _handleCommand(String command, String arg) async {
    switch (command) {
      case 'quit' || 'exit':
        onExit?.call();
      case 'help':
        transcript.openHelp(buildTuiHelpText(extra: _skillCommands));
      case 'new':
        await newSession();
      case 'sessions':
        await openPicker();
      case 'session':
        if (arg.isEmpty) {
          await openPicker();
        } else {
          await switchSession(arg);
        }
      case 'tools':
        _showTools();
      case 'mcp':
        _showMcp();
      case 'model':
        await _handleModel(arg);
      case 'provider':
        await _handleProvider(arg);
      case 'permission':
        await _handlePermission();
      case 'plan':
        _openPlanPanel();
      case 'goal':
        await _handleGoal(arg);
      case 'init':
        await _handleInit();
      case 'compact':
        await _handleCompact();
      case 'rewind':
        await _handleRewind(arg);
      case 'background':
        await _handleBackground(arg);
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
      case 'clear':
        transcript.clear();
      default:
        // 静态命令都不匹配时，把命令词当作技能名试一次。
        if (!await _runSkill(command, arg)) {
          transcript.add(
              TuiRole.system, '未知命令：/$command（/help 查看可用命令）');
        }
    }
    _refresh();
  }

  /// 当前可用的斜杠命令：静态表 + 技能注册表投影出的技能命令。
  List<TuiCommand> get commands => <TuiCommand>[...tuiCommands, ..._skillCommands];

  List<TuiCommand> get _skillCommands =>
      skillTuiCommands(_app.get<SkillRegistry>('skillRegistry'));

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
    final StringBuffer buffer =
        StringBuffer('已接入 MCP server（${registry.servers.length}）：');
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
        TuiRole.system, '已进入 Plan Mode：有副作用的工具被拦截，模型先规划再执行。$reviewNote');
  }

  /// `/compact`：手动压缩当前会话，把早期历史折叠成滚动摘要。
  ///
  /// 复用 Agent Loop 同款 LLM 汇总器（`summarizeEvents`），`keepRecent` 取
  /// [kManualCompactKeepRecent]（20 条）强制折叠；历史太短返回 `null` 不报错。
  Future<void> _handleCompact() async {
    final CompactionEngine? compactor = _app.get<CompactionEngine>('compaction');
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

  /// `/cost`：展示今日估算成本与 token 用量（护栏口径，非计费）。
  void _showCost() {
    final CostTracker? tracker = _app.get<CostTracker>('costTracker');
    if (tracker is! CostTrackerImpl) {
      transcript.add(TuiRole.system, '成本追踪不可用。');
      return;
    }
    transcript.add(
      TuiRole.system,
      '今日估算成本：\$${tracker.todayCost.toStringAsFixed(4)}'
      '（输入 ${tracker.promptTokens} / 输出 ${tracker.completionTokens} token，'
      '粗略护栏口径，非计费）',
    );
  }

  /// `/rewind [N]`：回滚 N 轮（缺省 1）——工作区文件 + 对话都回到该轮之前。
  /// `/rewind list` 列出本会话可用检查点。对话回滚用 `Session.fork`（append-only
  /// 不变式，非破坏派生）+ `SessionStore.adopt` 注册，再切到 fork 会话。
  Future<void> _handleRewind(String arg) async {
    final CheckpointManager? checkpoint =
        _app.get<CheckpointManager>('checkpointManager');
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
      final String counts = '恢复 ${result.restore.restored}、'
          '删除 ${result.restore.deleted} 个文件';
      if (session == null) {
        transcript.add(
          TuiRole.system,
          '已回滚工作区到第 ${result.turn} 轮（$counts）。',
        );
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
      announce: '已回滚到第 ${result.turn} 轮（$counts，对话已回到该轮），'
          '新会话 $forkId。',
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
    final BackgroundTaskService? service =
        _app.get<BackgroundTaskService>('backgroundTasks');
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
            '后台任务 $rest 输出：${output.isEmpty ? '（尚无输出）' : output}',
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
      buffer.write('\n  ${task.id} [${task.status.name}] ${task.command}'
          '（${task.elapsedMs}ms，输出 ${task.outputBytes}B）');
    }
    transcript.add(TuiRole.system, buffer.toString());
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

  /// `/init`：让模型扫描仓库并生成 / 更新 AGENTS.md。
  ///
  /// 不直接写文件：提交固定提示词走正常轮次，由模型经 write_file 落盘
  /// （沙箱限定工作区、审批照常）。
  Future<void> _handleInit() async {
    final String? workdir = _app.get<String>('workdir');
    final bool exists = workdir != null &&
        File('$workdir${Platform.pathSeparator}AGENTS.md').existsSync();
    if (exists) {
      transcript.add(TuiRole.system, 'AGENTS.md 已存在，将让模型先读取再更新。');
    }
    await submit(
      '扫描当前仓库（工作目录）的结构与关键文件，生成 AGENTS.md：'
      '项目概述、构建与测试命令、代码风格约定、边界与注意事项。'
      '${exists ? '文件已存在：先读取再改写，保留仍有用的内容。' : '文件不存在：用 write_file 创建到仓库根。'}',
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
    final CronTaskView view =
        cron.addDynamicTask(input, callerSessionId: _sessionId);
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
          '${parts[parts.length - 2]} ${parts[parts.length - 1]}');
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
      'daily' || '每天' || '每日' =>
        <String, Object?>{'prompt': prompt, 'daily': value},
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
    final RegExpMatch? match =
        RegExp(r'^每周([一二三四五六日天])$').firstMatch(kind);
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
        ..write('\n  ${view.id} [${view.enabled ? '启用' : '停用'}] '
            '${_cronScheduleText(view)}')
        ..write(view.nextRunAt == null
            ? ''
            : ' 下次=${_formatLocal(view.nextRunAt!)}')
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
        ..write('\n  #${record.seq} ${record.taskId} '
            '${_cronStatusText(record.status)} 排期=${_formatLocal(record.scheduledFor)}')
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

  /// `/permission`：打开权限模式选择面板（不经模型）。
  ///
  /// 选中后经 [applyPermissionMode] 持久化到会话并重挂审批中间件；取消不切换。
  Future<void> _handlePermission() async {
    final TuiPermissionMode? mode =
        await permissionPrompt.choose(_permissionMode);
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
      if (message.role == TuiRole.tool || message.role == TuiRole.thinking) {
        message.expanded = !message.expanded;
        _refresh();
        return;
      }
    }
  }

  /// 流式增量透传：思考 / 正文 delta 实时追加到屏上消息（同一条边到边增长），
  /// 终态结束本步流式。
  void _onLlmStream(LlmStreamEvent event) {
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
    final Context ctx = _app.plugin('tui-session:$id', (Context child) {
      provideAgentLoop(
        child,
        session: session,
        maxSteps: maxSteps,
        planning: planning,
        onStream: _onLlmStream,
      );
      // 计划闭环：plan_write 建计划，update_plan 在执行中推进。
      providePlanTool(child, session: session);
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
    _agent = ctx.agentLoop;
    _planMode = ctx.planMode;
    _goal = ctx.goal;
    // 检查点：绑定会话即写 turn 0 初始快照（供回滚到「全部轮次之前」）。
    final CheckpointManager? checkpoint =
        _app.get<CheckpointManager>('checkpointManager');
    if (checkpoint != null) {
      final String? error = await checkpoint.reset(
        id,
        lastEventId: session.lastEventId,
      );
      if (error != null) {
        transcript.add(TuiRole.system, error);
      }
    }
    // 权限模式按会话恢复：每个会话折叠自己的 permission/mode 后缀，
    // 同时清空审批门的「总是允许」清单（它也是会话级状态）。
    _gate?.resetAlwaysAllowed();
    _permissionMode = restorePermissionMode(session, fallback: initialPermissionMode);
    _syncPermissionMode();
    transcript.rebuildFrom(session);
    _eventSub = session.onEvent((SessionEvent event) {
      transcript.apply(event);
      _refresh();
    });
    _bindTeam(ctx);
    ready = true;
  }

  /// 绑定团队订阅与语音播报（装配了团队服务时生效）。
  void _bindTeam(Context ctx) {
    final AgentTeam? team = ctx.get<AgentTeam>('team');
    if (team == null) return;
    _teamSub = TeamSubscription(
      team: team,
      onChanged: (TeamSnapshot _) => _refresh(),
    );
    final TtsService? tts = this.tts;
    if (tts != null) {
      _voice = VoiceReporter(team: team, tts: tts, sink: ttsSink);
    }
  }

  void _unbind() {
    _eventSub?.call();
    _eventSub = null;
    _voice?.dispose();
    _voice = null;
    _approvalGate?.call();
    _approvalGate = null;
    _teamSub?.dispose();
    _teamSub = null;
    _app.get<CheckpointManager>('checkpointManager')?.detach();
    _queue.clear();
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
    final CheckpointManager? checkpoint =
        _app.get<CheckpointManager>('checkpointManager');
    if (checkpoint != null) {
      final String? error = await checkpoint.recordTurn(
        lastEventId: _session?.lastEventId,
      );
      if (error != null) {
        transcript.add(TuiRole.system, error);
      }
    }
    // 消息队列：收口后投递下一条排队输入（一次一条，依次衔接）。
    if (_queue.isNotEmpty && !busy) {
      final (String, List<TuiAttachment>) next = _queue.removeAt(0);
      unawaited(submit(next.$1, attachments: next.$2));
    }
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
      runtime?.finishRun(recordId,
          ok: ok, excerpt: excerpt.isEmpty ? null : excerpt);
    }
    _cronRuns.clear();
  }

  void _refresh() => onChanged?.call();
}

// conatus_code — 基于 conatus 运行时的终端编码智能体

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart'
    show SubAgentPermission, parseSubAgentPermission;
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';

Future<void> main(List<String> args) async {
  final TuiOptions options = TuiOptions.parse(args);
  if (options.helpRequested) {
    stdout.write(TuiOptions.usage);
    return;
  }
  if (options.versionRequested) {
    stdout.writeln('nava $navaVersion');
    return;
  }
  // `-p` 出现但没有任务文本：报错退出，而不是静默落回全交互 TUI——
  // 脚本里 `$TASK` 为空时否则会挂起等输入（E-16）。
  if (options.printRequested && options.print == null) {
    stderr.writeln('用法错误：-p / --print 缺少任务文本。');
    exit(2);
  }

  final ConatusCodeConfig config;
  try {
    config = loadConfig(path: options.configPath);
  } on ConfigException catch (error) {
    stderr.writeln('配置错误：${error.message}');
    exit(2);
  }

  // headless 安全闸门（E-9）：`-p` 不装审批链，OS 沙箱是唯一防线；沙箱被
  // 显式关掉时无人值守 = 裸奔，拒绝启动（除非 --allow-unsafe-headless 显式
  // 承担风险）。always_ask 这类显式加严的审批配置在 headless 落空时也不
  // 静默——启动就把话说清楚。
  final bool headless = options.print != null;
  final String? refusal = validateHeadlessSafety(
    headless: headless,
    sandbox: config.sandbox,
    allowUnsafe: options.allowUnsafeHeadless,
  );
  if (refusal != null) {
    stderr.writeln(refusal);
    exit(2);
  }
  final String? notice = approvalModeIgnoredNotice(
    headless: headless,
    approval: config.approval,
  );
  if (notice != null) {
    stderr.writeln(notice);
  } else {
    final String? askNotice = headlessAskNotice(
      headless: headless,
      approval: config.approval,
    );
    if (askNotice != null) stderr.writeln(askNotice);
  }

  final String workdir = config.agent.workdir ?? Directory.current.path;
  final String sep = Platform.pathSeparator;

  // 项目数据目录：缺省在 ~/.nava/projects/<编码工作区路径>（不污染工作区）；
  // 显式 [agent] project_dir 时才相对工作区。
  final String projectDataDir = resolveProjectDataDir(
    workdir: workdir,
    projectDir: config.agent.projectDir,
  );
  final String? configuredProjectDir = config.agent.projectDir;
  if (configuredProjectDir != null &&
      projectDirProtected(workdir, configuredProjectDir)) {
    stderr.writeln(
      '配置提示：[agent] project_dir 不能落在 .opencode（只读目录），'
      '已改用缺省数据目录 $projectDataDir。',
    );
  }

  // `--continue`：恢复最近一次会话（`--session` 优先；无历史则新建并提示）。
  String? initialSession = options.session;
  if (initialSession == null && options.continueRequested) {
    final String sessionDir = '$projectDataDir${sep}sessions';
    initialSession = findRecentSessionId(sessionDir);
    if (initialSession == null) {
      stderr.writeln('没有历史会话，已新建。');
    }
  }

  // 分层沙箱装配：
  // - Layer 1（fs_jail）：应用层文件 jail，纯应用层防误操作，任何平台可用；
  // - Layer 2（enabled）：OS 级沙箱，后端不可用时 fail-closed —— 注入拒斥
  //   执行器禁用命令，而不是整体退出或降级本地 shell。
  final String canonicalRoot = Directory(workdir).resolveSymbolicLinksSync();
  SandboxBackend? backend;
  if (config.sandbox.enabled) {
    try {
      backend = probeSandboxBackend();
    } on SandboxException catch (error) {
      stderr.writeln('OS 沙箱后端不可用（命令执行将禁用）：${error.message}');
    }
  }
  final SandboxLayers layers = resolveSandboxLayers(
    root: canonicalRoot,
    settings: config.sandbox,
    backend: backend,
  );

  final String? defaultModel = config.llm.defaultModel;
  String? provider;
  String? model;
  if (defaultModel != null) {
    final int slash = defaultModel.indexOf('/');
    provider = defaultModel.substring(0, slash);
    model = defaultModel.substring(slash + 1);
  }
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    baseDir: projectDataDir,
    configPath: resolveConfigPath(explicit: options.configPath),
    providers: config.providers,
    models: config.models,
    provider: provider,
    model: model,
    maxSteps: config.agent.maxSteps,
    subagentPermission:
        parseSubAgentPermission(config.agent.subagentPermission) ??
        SubAgentPermission.inherit,
    defaultAgent: config.agent.defaultAgent,
    retryPolicy: config.llm.retry.toPolicy(),
    fallbackModels: config.llm.fallbackModels,
    turnBudget: TurnBudget(
      maxDuration: config.budget.maxTurnSeconds == null
          ? null
          : Duration(seconds: config.budget.maxTurnSeconds!),
      maxTokens: config.budget.maxTurnTokens,
    ),
    credentials: ConfigCredentials(config),
    fs: layers.fs,
    shell: layers.shell,
    mcpServers: config.mcp.servers,
    interactive: !headless,
    workdir: workdir,
    checkpoint: config.checkpoint,
    xerj: config.xerj,
    background: config.background,
    hooks: config.hooks,
    lint: config.lint,
    formatter: config.formatter,
    story: config.story,
    permissions: config.permissions,
    approvalMode: config.approval.mode,
    instructions: config.instructions,
  );

  // headless：`-p <任务>` 单轮执行，跑完输出即退出（不启动 TUI）。
  // 异常（模型调用失败等）映射为退出码 1；配置错误与安全闸门已是 2。
  if (headless) {
    int code = 1;
    try {
      final HeadlessResult result = await runHeadless(
        runtime,
        prompt: options.print!,
        sessionId: initialSession,
      );
      stdout.writeln(
        renderHeadless(
          result,
          options.outputFormat == 'json'
              ? HeadlessFormat.json
              : HeadlessFormat.text,
        ),
      );
      code = result.exitCode;
    } catch (error) {
      stderr.writeln('headless 执行失败：$error');
    } finally {
      await runtime.dispose();
    }
    exit(code);
  }

  // 回退链与重试策略已在 runtime 上（`/model` 切换主模型时要跟着重建），
  // `createController` 直接取用，这里不重复传。
  final ConatusTuiController controller = runtime.createController(
    initialSession: initialSession,
    planning: true,
    initialPermissionMode: toTuiPermissionMode(config.approval.mode),
    onExit: shutdownApp,
  );
  await runApp(AgentTui(controller: controller));
  await runtime.dispose();
}

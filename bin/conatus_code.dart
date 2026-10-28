// conatus_code — 基于 conatus 运行时的终端编码智能体

import 'dart:convert';
import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart'
    show SubAgentPermission, parseSubAgentPermission;
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_harness/conatus_harness.dart';

Future<void> main(List<String> args) async {
  // `nava mcp ...` 与 `nava harness ...` 都是独立子命令：在 TUI 选项解析前分流。
  if (args.isNotEmpty && args.first == 'mcp') {
    exit(await runMcpCli(
      args.sublist(1),
      deps: const McpCliDeps(includeClaudeDesktop: true),
    ));
  }
  // 显式导入 OpenCode 配置：`nava import opencode [--write]`。
  if (args.isNotEmpty && args.first == 'import') {
    exit(await runImportCli(args.sublist(1)));
  }
  // 子命令先于选项解析：`harness` 是动词，不是选项值。
  if (args.isNotEmpty && args.first == 'harness') {
    exit(await runHarnessCommand(args.sublist(1)));
  }
  if (args.isNotEmpty && args.first == 'project') {
    exit(await runProjectCli(args.sublist(1)));
  }
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
  } on FileSystemException catch (error) {
    // 首次启动的模板写入可能被 `.opencode` 只读闸门拒绝：给一行可读错误，
    // 不要把 FileSystemException 的调用栈甩给用户。
    stderr.writeln('配置错误：无法写入 ${error.path ?? '配置文件'}（${error.message}）');
    exit(2);
  }

  // 主题是进程级全局状态：装配前落定，界面与浮层取色都用同一套 token。
  NavaTheme.use(config.tui.theme);
  for (final String warning in config.deprecations) {
    stderr.writeln(warning);
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

  final String workdir =
      options.workdir ?? config.agent.workdir ?? Directory.current.path;
  final String sep = Platform.pathSeparator;

  // 项目注册表：项目/工作区元数据进 ~/.nava/projects.db，数据落
  // ~/.nava/workspaces/<basename>-<hash>/。显式 [agent] project_dir 仍优先。
  final String? configuredProjectDir = config.agent.projectDir;
  final bool protectedProjectDir =
      configuredProjectDir != null &&
      projectDirProtected(workdir, configuredProjectDir);
  final String? projectDirOverride = protectedProjectDir
      ? null
      : configuredProjectDir;
  final ProjectRegistry projectRegistry;
  final WorkspaceInfo workspace;
  try {
    projectRegistry = ProjectRegistry.open();
    workspace = projectRegistry.resolve(
      workdir,
      dataDirOverride: projectDirOverride,
    );
  } catch (error) {
    stderr.writeln('项目注册表错误：$error');
    exit(2);
  }
  final String projectDataDir = workspace.dataDir;
  if (protectedProjectDir) {
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
  final List<ResolvedReference> references = resolveReferences(
    config.references,
    workdir: workdir,
    onWarning: stderr.writeln,
  );
  final SandboxLayers layers = resolveSandboxLayers(
    root: canonicalRoot,
    settings: config.sandbox,
    backend: backend,
    readOnlyPaths: <String>[for (final ResolvedReference ref in references) ref.path],
  );

  final String? defaultModel = config.llm.defaultModel;
  String? provider;
  String? model;
  if (defaultModel != null) {
    final int slash = defaultModel.indexOf('/');
    provider = defaultModel.substring(0, slash);
    model = defaultModel.substring(slash + 1);
  }
  final HarnessManifest? harness = _loadHarness(options.harnessPath);
  final List<McpServerSpec> mcpServers = loadEffectiveMcpServers(
    config: config,
    workdir: workdir,
    includeClaudeDesktop: true,
    onWarning: stderr.writeln,
  );
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    projectRegistry: projectRegistry,
    projectDir: projectDirOverride,
    configPath: resolveConfigPath(explicit: options.configPath),
    providers: config.providers,
    models: config.models,
    extraSkillDirs: config.extraSkillDirs,
    mergeAllSkills: config.mergeAllSkills,
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
    mcpServers: mcpServers,
    customTools: config.tools,
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
    configWarnings: config.deprecations,
    references: references,
    harness: harness,
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
  String? switchWorkdir;
  final ConatusTuiController controller = runtime.createController(
    initialSession: initialSession,
    planning: true,
    initialPermissionMode: toTuiPermissionMode(config.approval.mode),
    onExit: shutdownApp,
    onSwitchProject: (String workdir) {
      switchWorkdir = workdir;
      shutdownApp();
    },
    keybinds: config.keybinds,
  );
  await runApp(AgentTui(controller: controller));
  await runtime.dispose();
  if (switchWorkdir != null) {
    final List<String> childArgs = <String>[
      '--workdir',
      switchWorkdir!,
    ];
    if (options.configPath != null) {
      childArgs.addAll(<String>[
        '--config',
        File(options.configPath!).absolute.path,
      ]);
    }
    if (options.harnessPath != null) {
      childArgs.addAll(<String>[
        '--harness',
        File(options.harnessPath!).absolute.path,
      ]);
    }
    try {
      await Process.start(
        Platform.resolvedExecutable,
        childArgs,
        mode: ProcessStartMode.inheritStdio,
        workingDirectory: switchWorkdir,
      );
    } catch (error) {
      stderr.writeln('项目切换失败：$error');
      exit(2);
    }
    exit(0);
  }
}

/// 读取并解析 `--harness` 指定的 manifest；路径为空返回 `null`，失败即退出 2。
HarnessManifest? _loadHarness(String? path) {
  if (path == null) return null;
  try {
    final Object? raw = jsonDecode(File(path).readAsStringSync());
    if (raw is! Map<String, Object?>) {
      throw const FormatException('顶层必须是 JSON 对象');
    }
    return HarnessManifest.fromJson(raw);
  } on FileSystemException catch (error) {
    stderr.writeln('harness 读取失败：${error.message}');
    exit(2);
  } on FormatException catch (error) {
    stderr.writeln('harness 解析失败：${error.message}');
    exit(2);
  }
}

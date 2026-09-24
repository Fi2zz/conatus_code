// conatus_code — 基于 conatus 运行时的终端编码智能体

import 'dart:io';

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

  final ConatusCodeConfig config;
  try {
    config = loadConfig(path: options.configPath);
  } on ConfigException catch (error) {
    stderr.writeln('配置错误：${error.message}');
    exit(2);
  }

  final String workdir = config.agent.workdir ?? Directory.current.path;
  final String sep = Platform.pathSeparator;

  // `--continue`：恢复最近一次会话（`--session` 优先；无历史则新建并提示）。
  String? initialSession = options.session;
  if (initialSession == null && options.continueRequested) {
    final String sessionDir =
        '$workdir$sep${config.agent.projectDir}${sep}sessions';
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
    baseDir: '$workdir$sep${config.agent.projectDir}',
    configPath: resolveConfigPath(explicit: options.configPath),
    providers: config.providers,
    models: config.models,
    provider: provider,
    model: model,
    maxSteps: config.agent.maxSteps,
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
    interactive: options.print == null,
    workdir: workdir,
    checkpoint: config.checkpoint,
  );

  // headless：`-p <任务>` 单轮执行，跑完输出即退出（不启动 TUI）。
  // 异常（模型调用失败等）映射为退出码 1；配置错误已是 2。
  if (options.print != null) {
    int code = 1;
    try {
      final HeadlessResult result = await runHeadless(
        runtime,
        prompt: options.print!,
        sessionId: initialSession,
      );
      stdout.writeln(renderHeadless(
        result,
        options.outputFormat == 'json'
            ? HeadlessFormat.json
            : HeadlessFormat.text,
      ));
      code = result.exitCode;
    } catch (error) {
      stderr.writeln('headless 执行失败：$error');
    } finally {
      await runtime.dispose();
    }
    exit(code);
  }

  final ConatusTuiController controller = runtime.createController(
    initialSession: initialSession,
    planning: true,
    initialPermissionMode: toTuiPermissionMode(config.approval.mode),
    onExit: shutdownApp,
  );
  await runApp(AgentTui(controller: controller));
  await runtime.dispose();
}

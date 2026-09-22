// conatus_code — 基于 conatus 运行时的终端编码智能体

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

Future<void> main(List<String> args) async {
  final TuiOptions options = TuiOptions.parse(args);
  if (options.helpRequested) {
    stdout.write(TuiOptions.usage);
    return;
  }

  final ConatusCodeConfig config;
  try {
    config = loadConfig(path: options.configPath);
  } on ConfigException catch (error) {
    stderr.writeln('配置错误：${error.message}');
    exit(1);
  }

  final String workdir = config.agent.workdir ?? Directory.current.path;
  final String sep = Platform.pathSeparator;

  // 沙箱装配：启用则 jail 文件系统 + 沙箱命令执行；后端不可用即 fail-closed。
  final FileSystem? sandboxedFs;
  final ShellExecutor? sandboxedShell;
  if (config.sandbox.enabled) {
    try {
      final SandboxBackend backend = probeSandboxBackend();
      final String canonicalRoot = Directory(workdir).resolveSymbolicLinksSync();
      final Set<String>? executables = config.sandbox.allowedExecutables.isEmpty
          ? null
          : config.sandbox.allowedExecutables.toSet();
      sandboxedFs = JailedFileSystem(root: canonicalRoot);
      sandboxedShell = SandboxedShellExecutor(
        options: SandboxedShellOptions(
          backend: backend,
          root: canonicalRoot,
          commandPolicy: CommandPolicy(
            root: canonicalRoot,
            allowedExecutables: executables,
          ),
          networkAllowlist: config.sandbox.networkAllowlist.toSet(),
          maxOutputBytes: config.sandbox.maxOutputBytes,
          maxTimeoutMs: config.sandbox.commandTimeoutMs,
        ),
      );
    } on SandboxException catch (error) {
      stderr.writeln('沙箱不可用（fail-closed，未执行任何命令）：${error.message}');
      exit(1);
    }
  } else {
    sandboxedFs = null;
    sandboxedShell = null;
  }

  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    baseDir: '$workdir$sep${config.agent.projectDir}',
    model: config.llm.model,
    maxSteps: config.agent.maxSteps,
    turnBudget: TurnBudget(
      maxDuration: config.budget.maxTurnSeconds == null
          ? null
          : Duration(seconds: config.budget.maxTurnSeconds!),
      maxTokens: config.budget.maxTurnTokens,
    ),
    credentials: ConfigCredentials(config),
    exaApiKey: Platform.environment['EXA_API_KEY'],
    fs: sandboxedFs,
    shell: sandboxedShell,
  );

  final ConatusTuiController controller = runtime.createController(
    initialSession: options.session,
    initialPermissionMode: toTuiPermissionMode(config.approval.mode),
    onExit: shutdownApp,
  );
  await runApp(AgentTui(controller: controller, firstInput: options.first));
  await runtime.dispose();
}

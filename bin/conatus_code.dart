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

  final ConatusCodeConfig config;
  try {
    config = loadConfig(path: options.configPath);
  } on ConfigException catch (error) {
    stderr.writeln('配置错误：${error.message}');
    exit(1);
  }

  final String workdir = config.agent.workdir ?? Directory.current.path;
  final String sep = Platform.pathSeparator;
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    baseDir: '$workdir$sep${config.agent.projectDir}',
    model: config.llm.model,
    maxSteps: config.agent.maxSteps,
    credentials: ConfigCredentials(config),
    exaApiKey: Platform.environment['EXA_API_KEY'],
  );

  final ConatusTuiController controller = runtime.createController(
    initialSession: options.session,
    initialPermissionMode: toTuiPermissionMode(config.approval.mode),
    onExit: shutdownApp,
  );
  await runApp(AgentTui(controller: controller, firstInput: options.first));
  await runtime.dispose();
}

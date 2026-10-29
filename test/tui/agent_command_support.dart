/// 自定义命令 / Agent 选择测试的共用装配。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/providers.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

import 'agent_command_fakes.dart';

/// 装配好的命令测试环境。
class CommandHarness {
  CommandHarness._({
    required this.root,
    required this.work,
    required this.app,
    required this.controller,
    required this.provider,
    required this.spawn,
    required this.mutate,
    required this.exited,
  });

  /// 临时根目录。
  final Directory root;

  /// 工作目录（命令 / Agent 文件写在这里）。
  final Directory work;

  /// 根上下文。
  final Context app;

  /// 会话控制器。
  final ConatusTuiController controller;

  /// 模型替身。
  final CommandCaptureProvider provider;

  /// 假 task。
  final FakeSpawnTool spawn;

  /// 假副作用工具（Plan Mode 拦截断言）。
  final FakeMutateTool mutate;

  /// `/exit` 是否触发（可变标志）。
  final List<bool> exited;

  /// 释放上下文并删除临时目录。
  Future<void> dispose() async {
    app.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

/// 装配测试环境。
///
/// [registry] 非空时启用真实 provider 链（请求走 MockClient），用于验证模型
/// 覆盖；否则使用 [CommandCaptureProvider]。
Future<CommandHarness> buildCommandHarness({
  Map<String, String> commands = const <String, String>{},
  Map<String, String> agents = const <String, String>{},
  Map<String, String> extraFiles = const <String, String>{},
  bool withShell = false,
  bool withSpawn = false,
  bool withCompaction = false,
  String? defaultAgent,
  ProviderRegistry? registry,
  List<String> chainEntries = const <String>[],
}) async {
  final Directory root = Directory.systemTemp.createTempSync('nava-cmd-');
  final Directory work = Directory('${root.path}/work')..createSync();
  final Directory home = Directory('${root.path}/home')..createSync();
  _writeFiles(work, extraFiles);
  _writeFiles(work, <String, String>{
    for (final MapEntry<String, String> entry in commands.entries)
      '.nava/commands/${entry.key}': entry.value,
  });
  _writeFiles(work, <String, String>{
    for (final MapEntry<String, String> entry in agents.entries)
      '.nava/agents/${entry.key}': entry.value,
  });
  final CommandRegistry commandRegistry = await CommandRegistry.load(
    workdir: work.path,
    home: home.path,
  );
  final AgentRegistry agentRegistry = await AgentRegistry.load(
    workdir: work.path,
    home: home.path,
    defaultId: defaultAgent,
  );

  final Context app = Context.root();
  provideTools(app);
  provideSystemPrompt(app);
  final CommandCaptureProvider provider = CommandCaptureProvider();
  final FakeSpawnTool spawn = FakeSpawnTool();
  final FakeMutateTool mutate = FakeMutateTool();
  app.tools.register(mutate);
  if (withSpawn) app.tools.register(spawn);
  Disposer llmDisposer;
  if (registry == null) {
    llmDisposer = provideLlm(app, llm: FallbackLlm(<LlmProvider>[provider]));
  } else {
    final LlmChain chain = buildLlmChain(
      registry,
      entries: chainEntries,
      policy: const RetryPolicy(),
    )!;
    llmDisposer = provideLlm(app, llm: chain.llm);
    app.provide('llmChainSlot', LlmChainSlot(chain));
    app.provide('providers', registry);
  }
  if (withShell) provideShellLocal(app);
  if (withCompaction) provideCompaction(app);
  provideMemory(app);
  final SessionStore sessions = provideSessions(app);
  final PermissionWiring wiring = PermissionWiring(
    store: PermissionStore('${root.path}/permissions.json'),
    workdir: work.path,
  );
  app.provide('permissionWiring', wiring);
  app.provide(kPermissionScopeService, wiring.slot);
  instrumentPermission(app);
  app.provide('commandRegistry', commandRegistry);
  app.provide('agentRegistry', agentRegistry);

  final List<bool> exited = <bool>[false];
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: registry?.byName(registry.currentName)?.defaultModel ?? 'mock',
    onExit: () => exited[0] = true,
  );
  _wireLlmSwap(app, controller, llmDisposer);
  provider.onPrompt = (String prompt) => provider.turns.add(
    CapturedTurn(
      prompt: prompt,
      agentId: controller.agentId,
      planModeActive: controller.planModeActive,
    ),
  );
  await controller.start();
  return CommandHarness._(
    root: root,
    work: work,
    app: app,
    controller: controller,
    provider: provider,
    spawn: spawn,
    mutate: mutate,
    exited: exited,
  );
}

void _writeFiles(Directory work, Map<String, String> files) {
  for (final MapEntry<String, String> entry in files.entries) {
    final File file = File('${work.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
}

void _wireLlmSwap(
  Context app,
  ConatusTuiController controller,
  Disposer initial,
) {
  Disposer disposer = initial;
  controller.switchLlm = (FallbackLlm next) {
    disposer();
    disposer = provideBudgetedLlm(app, llm: next, budget: const TurnBudget());
  };
}

/// 注册表断言辅助：按 ID 找列表下标。
int indexOfAgent(List<AgentDefinition> list, String id) =>
    list.indexWhere((AgentDefinition agent) => agent.id == id);

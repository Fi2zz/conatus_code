/// `/doctor`：体检聚合与命令展示。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/providers.dart';
import 'package:conatus_code/src/plugins/plugin_config.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _StubProvider implements LlmProvider {
  @override
  String get name => 'stub';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async => const LlmResult(content: 'ok', provider: 'stub', model: 'm');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 假插件服务：只覆盖 `/doctor` 用到的诊断字段。
class _FakePlugins implements PluginServiceLike {
  _FakePlugins({
    this.available = true,
    this.warnings = const <String>[],
    this.pluginCount = 0,
    this.toolCount = 0,
    this.skillRoots = const <String>[],
  });

  @override
  final bool available;

  @override
  final List<String> warnings;

  @override
  final int pluginCount;

  @override
  final int toolCount;

  @override
  final List<String> skillRoots;

  @override
  String get contextText => '';

  @override
  Map<String, String> get shellEnv => const <String, String>{};

  @override
  Future<void> notify(
    String event, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) async {}
}

Future<(ConatusTuiController, Context)> _build() async {
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    onExit: () {},
  );
  await controller.start();
  return (controller, app);
}

void main() {
  test('doctorChecks 空装配：配置/provider 未通过，工具通过', () async {
    final (ConatusTuiController controller, Context app) = await _build();
    addTearDown(app.dispose);

    final List<DoctorCheck> checks = doctorChecks(app);

    expect(checks.firstWhere((DoctorCheck c) => c.name == '配置文件').ok, isFalse);
    expect(checks.firstWhere((DoctorCheck c) => c.name == '模型提供商').ok, isFalse);
    expect(checks.firstWhere((DoctorCheck c) => c.name == '工具表').ok, isTrue);
    expect(
      checks.firstWhere((DoctorCheck c) => c.name == 'MCP server').ok,
      isFalse,
    );
  });

  test('/doctor 输出逐项标记与汇总', () async {
    final (ConatusTuiController controller, Context app) = await _build();
    addTearDown(app.dispose);

    await controller.handleLine('/doctor');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('nava 体检'));
    expect(text, contains('✓ 工具表'));
    expect(text, contains('✗ 模型提供商'));
    expect(text, contains('需处理项'));
  });

  test('命令表包含 doctor', () {
    expect(tuiCommands.any((TuiCommand c) => c.name == 'doctor'), isTrue);
  });

  test('未采集启动耗时时 /doctor 标注未采集', () async {
    final (ConatusTuiController controller, Context app) = await _build();
    addTearDown(app.dispose);

    await controller.handleLine('/doctor');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('启动耗时 — 未采集'));
  });

  test('启动耗时进入 /doctor：总耗时与分阶段明细', () async {
    final (ConatusTuiController controller, Context app) = await _build();
    addTearDown(app.dispose);
    Duration fake = Duration.zero;
    final StartupTiming timing = StartupTiming(now: () => fake);
    fake = const Duration(milliseconds: 38);
    timing.markConfigLoaded();
    fake = const Duration(milliseconds: 358);
    timing.markRuntimeReady();
    fake = const Duration(milliseconds: 412);
    timing.markFirstFrame();
    app.provide('startupTiming', timing);

    await controller.handleLine('/doctor');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('启动耗时 — 总 412ms（配置 38 · 装配 320 · 首帧 54）'));
  });

  test('配置废弃项进入 /doctor', () async {
    final (ConatusTuiController controller, Context app) = await _build();
    addTearDown(app.dispose);
    app.provide('configWarnings', <String>['config.toml：thinking 已废弃（当前无效果）。']);

    await controller.handleLine('/doctor');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('配置废弃项'));
    expect(text, contains('thinking'));
  });

  test('Agent / 命令发现告警进入 /doctor，带来源文件与原因', () async {
    final (ConatusTuiController controller, Context app) = await _build();
    addTearDown(app.dispose);
    final Directory work = Directory.systemTemp.createTempSync('nava-doctor-');
    final Directory home = Directory.systemTemp.createTempSync('nava-doc-h-');
    addTearDown(() {
      work.deleteSync(recursive: true);
      home.deleteSync(recursive: true);
    });
    File('${work.path}/.nava/commands/bad.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('---\nagent: 1\n---\nbad\n');
    File('${work.path}/.nava/agents/bad.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('---\nmode: nope\n---\nbad\n');
    File('${work.path}/.nava/agents/model.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('---\nmode: subagent\nmodel: nope/gpt-x\n---\nbad\n');
    app.provide(
      'commandRegistry',
      await CommandRegistry.load(workdir: work.path, home: home.path),
    );
    final AgentRegistry agents = await AgentRegistry.load(
      workdir: work.path,
      home: home.path,
    );
    app.provide('agentRegistry', agents);
    final AgentProfileResolver profiles = AgentProfileResolver(
      registry: agents,
      providers: ProviderRegistry(profiles: <ProviderProfile>[]),
    );
    await profiles.validateModels();
    app.provide('agentProfiles', profiles);

    await controller.handleLine('/doctor');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('Agent / 命令发现'));
    expect(text, contains('bad.md'));
    expect(text, contains('nope/gpt-x'));
  });

  test('插件未装配：/doctor 如实标注', () async {
    final (ConatusTuiController controller, Context app) = await _build();
    addTearDown(app.dispose);

    await controller.handleLine('/doctor');

    expect(
      controller.transcript.messages.last.text,
      contains('✓ 插件 — 未装配'),
    );
  });

  test('插件未加载（如缺 node）：⚠ 并带上原因', () async {
    final (ConatusTuiController controller, Context app) = await _build();
    addTearDown(app.dispose);
    app.provide(
      'plugins',
      _FakePlugins(
        available: false,
        warnings: <String>['未找到 node，插件未加载。'],
      ),
    );

    await controller.handleLine('/doctor');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('⚠ 插件'));
    expect(text, contains('未找到 node'));
  });

  test('插件已加载：显示数量与工具/技能根', () async {
    final (ConatusTuiController controller, Context app) = await _build();
    addTearDown(app.dispose);
    app.provide(
      'plugins',
      _FakePlugins(
        pluginCount: 2,
        toolCount: 3,
        skillRoots: const <String>['/plugins/skills'],
      ),
    );

    await controller.handleLine('/doctor');

    expect(
      controller.transcript.messages.last.text,
      contains('✓ 插件 — 2 个 · 工具 3 · 技能根 1'),
    );
  });
}

/// `/doctor`：体检聚合与命令展示。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/providers.dart';
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
}

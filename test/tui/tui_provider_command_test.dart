/// `/provider` 只读展示与 `/model` 直接切换模型名。
library;

import 'dart:io';

import 'package:conatus_code/providers.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 固定回复的假 provider。
class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this._name);

  final String _name;

  @override
  String get name => _name;

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      LlmResult(content: 'ok', provider: _name, model: 'm');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

ProviderProfile _profile(String name) => ProviderProfile(
      name: name,
      baseUrl: 'https://$name.example/v1',
      credentialKey: '${name.toUpperCase()}_API_KEY',
      models: <String>['$name-small', '$name-large'],
    );

Future<(ConatusTuiController, Context, Directory)> _build({
  bool withProviders = true,
}) async {
  final Directory dir = Directory.systemTemp.createTempSync('tui-provider-');
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider('initial')]));
  provideMemory(app);
  if (withProviders) {
    provideProviders(
      app,
      providers: <ProviderProfile>[_profile('a'), _profile('b')],
      currentName: 'a',
    );
  }
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    initialSession: 's1',
    modelLabel: 'a-small',
    onExit: () {},
  );
  await controller.start();
  return (controller, app, dir);
}

void main() {
  test('未装配注册表时 /provider 提示未装配', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build(withProviders: false);

    await controller.handleLine('/provider');

    expect(controller.transcript.messages.single.text, contains('未装配'));
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/provider 只读展示：列出 provider 与当前标记', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();

    await controller.handleLine('/provider');

    expect(controller.providerPrompt.open, isTrue);
    expect(
      controller.providerPrompt.items.map((TuiProviderItem i) => i.label),
      <String>['a', 'b'],
    );
    expect(controller.providerPrompt.selected?.name, 'a');
    expect(controller.providerPrompt.selected?.current, isTrue);
    expect(
      controller.providerPrompt.items.map((TuiProviderItem i) => i.current),
      <bool>[true, false],
    );
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/provider 只读：忽略参数，不切换不删除', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();

    await controller.handleLine('/provider b');

    expect(controller.providerPrompt.open, isTrue);
    expect(app.providers!.currentName, 'a');
    expect(app.providers!.byName('a'), isNotNull);
    expect(
      controller.transcript.messages
          .where((TuiMessage m) => m.text.contains('已切换到')),
      isEmpty,
    );
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/model <名字> 直接切换：换 LLM 服务、更新标签、重绑', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();
    final List<String> swapped = <String>[];
    controller.switchLlm =
        (FallbackLlm llm) => swapped.add(llm.providers.first.name);

    await controller.handleLine('/model a-large');

    expect(swapped, <String>['a']);
    expect(controller.modelLabel, 'a-large');
    expect(controller.modelPrompt.open, isFalse);
    expect(controller.transcript.messages.last.text, contains('已切换到 a'));
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/model 无参：提示当前提供商与用法，不打开浮层', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();

    await controller.handleLine('/model');

    expect(controller.modelPrompt.open, isFalse);
    expect(controller.transcript.messages.last.text, contains('当前提供商：a'));
    expect(controller.transcript.messages.last.text, contains('用法：/model <模型名>'));
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/model 与 /provider 是无参命令：菜单 Enter 直接运行', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();

    final TuiCommand model = controller.commands
        .firstWhere((TuiCommand c) => c.name == 'model');
    final TuiCommand provider = controller.commands
        .firstWhere((TuiCommand c) => c.name == 'provider');
    expect(model.takesArgs, isFalse);
    expect(provider.takesArgs, isFalse);

    await controller.handleLine(model.token);
    expect(controller.modelPrompt.open, isFalse);
    expect(controller.transcript.messages.last.text, contains('用法：/model'));

    await controller.handleLine(provider.token);
    expect(controller.providerPrompt.open, isTrue);
    app.dispose();
    dir.deleteSync(recursive: true);
  });
}

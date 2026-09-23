/// `/provider` 展示与新增、`/model` 打开模型浮层选择。
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
  bool emptyProviders = false,
  bool providerSetupNeeded = false,
}) async {
  final Directory dir = Directory.systemTemp.createTempSync('tui-provider-');
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider('initial')]));
  provideMemory(app);
  if (withProviders) {
    provideProviders(
      app,
      providers: emptyProviders
          ? const <ProviderProfile>[]
          : <ProviderProfile>[_profile('a'), _profile('b')],
      currentName: emptyProviders ? null : 'a',
    );
  }
  if (providerSetupNeeded) {
    app.provide('providerSetupNeeded', true);
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

/// 无模型清单的 provider 装配（`/model` 兜底与空列表用例）。
///
/// [devCatalog] 非空时注入 models.dev 桩，避免测试触网。
Future<(ConatusTuiController, Context, Directory)> _buildBare({
  String modelLabel = '',
  Map<String, List<ModelsDevModel>>? devCatalog,
}) async {
  final Directory dir = Directory.systemTemp.createTempSync('tui-model-');
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider('initial')]));
  provideMemory(app);
  provideProviders(
    app,
    providers: <ProviderProfile>[
      const ProviderProfile(
        name: 'a',
        baseUrl: 'https://a.example/v1',
        credentialKey: 'A_API_KEY',
      ),
    ],
    currentName: 'a',
  );
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    initialSession: 's1',
    modelLabel: modelLabel,
    onExit: () {},
  );
  if (devCatalog != null) {
    controller.modelsDevLoader = () async => devCatalog;
  }
  await controller.start();
  return (controller, app, dir);
}

/// models.dev 桩模型（默认支持工具调用与推理，即能进编码清单）。
ModelsDevModel _devModel(String id, {bool toolCall = true}) => ModelsDevModel(
      id: id,
      name: id,
      toolCall: toolCall,
      reasoning: true,
      attachment: false,
      contextLength: 16000,
      costInput: 0,
      costOutput: 0,
      inputModalities: const <String>['text'],
    );

void main() {
  test('未装配注册表时 /provider 提示未装配', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build(withProviders: false);

    await controller.handleLine('/provider');

    expect(controller.transcript.messages.single.text, contains('未装配'));
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('未配置 provider 时启动自动打开引导面板', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build(emptyProviders: true, providerSetupNeeded: true);

    expect(controller.providerPrompt.open, isTrue);
    expect(
      controller.providerPrompt.items.map((TuiProviderItem i) => i.label),
      <String>['[ Add New Platform ]'],
    );
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/provider 展示：列出 provider、当前标记与新增入口', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();

    await controller.handleLine('/provider');

    expect(controller.providerPrompt.open, isTrue);
    expect(
      controller.providerPrompt.items.map((TuiProviderItem i) => i.label),
      <String>['a', 'b', '[ Add New Platform ]'],
    );
    expect(controller.providerPrompt.selected?.name, 'a');
    expect(controller.providerPrompt.selected?.current, isTrue);
    expect(
      controller.providerPrompt.items.map((TuiProviderItem i) => i.current),
      <bool>[true, false, false],
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

  test('/model 打开浮层：列出当前提供商的模型', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();
    final Future<void> pending = controller.handleLine('/model');
    await Future<void>.delayed(Duration.zero);

    expect(controller.modelPrompt.open, isTrue);
    final List<String> models = controller.modelPrompt.matches
        .map((TuiModelItem i) => i.model)
        .toList();
    expect(models, <String>['a-small', 'a-large']);
    expect(
      controller.modelPrompt.matches.where((TuiModelItem i) => i.current),
      hasLength(1),
    );

    controller.modelPrompt.cancel();
    await pending;
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/model 浮层 Enter 选中切换模型', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();
    final List<String> swapped = <String>[];
    controller.switchLlm =
        (FallbackLlm llm) => swapped.add(llm.providers.first.name);
    final Future<void> pending = controller.handleLine('/model');
    await Future<void>.delayed(Duration.zero);

    controller.modelPrompt.move(1); // a-small → a-large
    controller.modelPrompt.confirm();
    await pending;

    expect(swapped, <String>['a']);
    expect(controller.modelLabel, 'a-large');
    expect(controller.modelPrompt.open, isFalse);
    expect(controller.transcript.messages.last.text, contains('已切换到 a'));
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/model 浮层 Esc 取消：不切换', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();
    final List<String> swapped = <String>[];
    controller.switchLlm =
        (FallbackLlm llm) => swapped.add(llm.providers.first.name);
    final Future<void> pending = controller.handleLine('/model');
    await Future<void>.delayed(Duration.zero);

    controller.modelPrompt.cancel();
    await pending;

    expect(swapped, isEmpty);
    expect(controller.modelPrompt.open, isFalse);
    expect(controller.transcript.messages.last.text, contains('已取消模型切换'));
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/model <片段> 预填搜索框过滤', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();
    final Future<void> pending = controller.handleLine('/model a-');
    await Future<void>.delayed(Duration.zero);

    expect(controller.modelPrompt.open, isTrue);
    expect(controller.modelPrompt.query, 'a-');
    expect(controller.modelPrompt.search.text, 'a-');
    expect(controller.modelPrompt.matches, hasLength(2));

    controller.modelPrompt.cancel();
    await pending;
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/model 列表为空仍打开浮层', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _buildBare(devCatalog: <String, List<ModelsDevModel>>{});
    final Future<void> pending = controller.handleLine('/model');
    await Future<void>.delayed(Duration.zero);

    expect(controller.modelPrompt.open, isTrue);
    expect(controller.modelPrompt.matches, isEmpty);

    controller.modelPrompt.cancel();
    await pending;
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/model 配置无清单时从 models.dev 兜底', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _buildBare(
      modelLabel: 'x-current',
      devCatalog: <String, List<ModelsDevModel>>{
        'a': <ModelsDevModel>[_devModel('c-m1'), _devModel('c-m2', toolCall: false)],
      },
    );
    final Future<void> pending = controller.handleLine('/model');
    await Future<void>.delayed(Duration.zero);

    expect(controller.modelPrompt.open, isTrue);
    final List<String> models = controller.modelPrompt.matches
        .map((TuiModelItem i) => i.model)
        .toList();
    // c-m2 不支持工具调用，被 keepForCoding 过滤。
    expect(models, <String>['x-current', 'c-m1']);

    controller.modelPrompt.cancel();
    await pending;
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

    final Future<void> pending = controller.handleLine(model.token);
    await Future<void>.delayed(Duration.zero);
    expect(controller.modelPrompt.open, isTrue);
    controller.modelPrompt.cancel();
    await pending;

    await controller.handleLine(provider.token);
    expect(controller.providerPrompt.open, isTrue);
    app.dispose();
    dir.deleteSync(recursive: true);
  });
}

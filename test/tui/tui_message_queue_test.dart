/// 消息队列：busy 入队、收口依次出队、容量上限、打断/切会话清空。
library;

import 'dart:async';

import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 第一轮挂起直到 [gate] 放行；记录收到的 prompt 顺序。
class _GateProvider implements LlmProvider {
  final Completer<void> gate = Completer<void>();
  final List<String> prompts = <String>[];
  int calls = 0;

  @override
  String get name => 'gated';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    prompts.add(messages.last.content);
    calls++;
    if (calls == 1) await gate.future;
    return LlmResult(content: 'reply-$calls', provider: 'gated', model: 'm');
  }

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

Future<(ConatusTuiController, Context, _GateProvider)> _build() async {
  final Context app = Context.root();
  provideTools(app);
  final _GateProvider provider = _GateProvider();
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[provider]));
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    onExit: () {},
  );
  await controller.start();
  return (controller, app, provider);
}

/// 轮询直到 [cond] 成立（超时上限 2s）。
Future<void> _until(bool Function() cond) async {
  for (int i = 0; i < 400 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(cond(), isTrue, reason: '条件未在超时内成立');
}

void main() {
  test('busy 时入队，收口后依次出队执行', () async {
    final (ConatusTuiController controller, Context app, _GateProvider provider) =
        await _build();
    addTearDown(app.dispose);

    final Future<void> first = controller.handleLine('第一条');
    await _until(() => controller.busy);

    await controller.handleLine('第二条');
    expect(controller.queuedCount, 1);
    expect(controller.transcript.messages.last.text, contains('已排队'));

    await controller.handleLine('第三条');
    expect(controller.queuedCount, 2);

    provider.gate.complete(); // 放行第一轮
    await first;
    await _until(() => !controller.busy && controller.queuedCount == 0);

    expect(provider.prompts, <String>['第一条', '第二条', '第三条']);
  });

  test('队列满（20 条）拒绝新输入', () async {
    final (ConatusTuiController controller, Context app, _GateProvider provider) =
        await _build();
    addTearDown(app.dispose);

    final Future<void> first = controller.handleLine('打头');
    await _until(() => controller.busy);
    for (int i = 0; i < kMessageQueueCap; i++) {
      await controller.handleLine('排队-$i');
    }
    expect(controller.queuedCount, kMessageQueueCap);

    await controller.handleLine('第 21 条');
    expect(controller.transcript.messages.last.text, contains('排队已满'));

    provider.gate.complete();
    await first;
  });

  test('Esc 打断清空队列并提示条数', () async {
    final (ConatusTuiController controller, Context app, _GateProvider provider) =
        await _build();
    addTearDown(app.dispose);

    final Future<void> first = controller.handleLine('进行中');
    await _until(() => controller.busy);
    await controller.handleLine('排队-A');
    await controller.handleLine('排队-B');
    expect(controller.queuedCount, 2);

    controller.interrupt();

    expect(controller.queuedCount, 0);
    expect(controller.transcript.messages.last.text, contains('已清空 2 条'));
    provider.gate.complete();
    await first;
  });

  test('切换会话清空队列', () async {
    final (ConatusTuiController controller, Context app, _GateProvider provider) =
        await _build();
    addTearDown(app.dispose);

    final Future<void> first = controller.handleLine('进行中');
    await _until(() => controller.busy);
    await controller.handleLine('排队');
    expect(controller.queuedCount, 1);

    await controller.switchSession('session_11111111-2222-3333-4444-555555555555');

    expect(controller.queuedCount, 0);
    provider.gate.complete();
    await first;
  });

  test('空闲时 submit 直接执行不入队', () async {
    final (ConatusTuiController controller, Context app, _GateProvider provider) =
        await _build();
    addTearDown(app.dispose);
    provider.gate.complete(); // 放行首轮，避免挂起

    await controller.handleLine('直接执行');
    expect(controller.queuedCount, 0);
    expect(provider.prompts, <String>['直接执行']);
  });
}

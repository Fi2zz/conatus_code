/// 消息队列：busy 入队、收口依次出队、容量上限、打断/切会话清空。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 第一轮挂起直到 [gate] 放行；记录收到的 prompt 顺序。
class _GateProvider implements LlmProvider {
  final Completer<void> gate = Completer<void>();
  final List<String> prompts = <String>[];
  final List<List<String>> batches = <List<String>>[];
  final List<List<LlmMessage>> messagesSeen = <List<LlmMessage>>[];
  bool toolCallOnFirst = false;
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
    batches.add(messages.map((LlmMessage m) => m.content).toList());
    messagesSeen.add(List<LlmMessage>.of(messages));
    calls++;
    if (calls == 1) {
      await gate.future;
      if (toolCallOnFirst) {
        return const LlmResult(
          content: '',
          provider: 'gated',
          model: 'm',
          toolCalls: <LlmToolCall>[LlmToolCall(id: 't1', name: 'echo')],
        );
      }
    }
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
  app.tools.fn(
    'echo',
    description: '回显',
    handler: (ToolContext ctx) async => ToolResult.success('ok'),
  );
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
  test('busy 时入队，下一次请求边界注入（轮末兜底）', () async {
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
    await _until(() => provider.calls >= 2);
    await _until(() => !controller.busy && controller.queuedCount == 0);

    // 第一轮收口后兜底投递「第二条」；「第三条」在该轮请求边界被 steering
    // 注入，因此第二轮一次带上两条，模型只被调用两次。
    expect(provider.calls, 2);
    expect(provider.batches[1], containsAll(<String>['第二条', '第三条']));
  });

  test('排队消息的附件不被 steering 吞掉（轮末兜底原样投递）', () async {
    final (ConatusTuiController controller, Context app, _GateProvider provider) =
        await _build();
    provider.toolCallOnFirst = true;
    addTearDown(app.dispose);
    final Directory dir =
        Directory.systemTemp.createTempSync('nava-queue-attach-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final File image = File('${dir.path}/img.png')
      ..writeAsBytesSync(<int>[0x89, 0x50, 0x4e, 0x47]);

    final Future<void> first = controller.handleLine('第一条');
    await _until(() => controller.busy);
    await controller.handleLine(
      '带图',
      attachments: <TuiAttachment>[
        TuiAttachment(path: image.path, mimeType: 'image/png'),
      ],
    );
    expect(controller.queuedCount, 1);

    provider.gate.complete();
    await first;
    await _until(() => provider.calls >= 3);

    final bool carried = provider.messagesSeen.any(
      (List<LlmMessage> batch) => batch.any(
        (LlmMessage m) => m.role == 'user' && m.images.isNotEmpty,
      ),
    );
    expect(carried, isTrue);
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

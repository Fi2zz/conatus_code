/// 排队消息轮内注入：busy 时排队的消息在 Agent Loop 组下一次模型请求前
/// 经 steering 缝注入会话；注入后队列清空、轮末不重复发送；Esc 打断时已
/// 注入的消息留在会话。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 第一次请求返回工具调用（工具等 [toolGate] 放行），第二次请求收口
/// （[hangSecond] 时等 [secondGate]，供 Esc 用例把轮次挂住）。
class _SteeringProvider implements LlmProvider {
  final Completer<void> toolGate = Completer<void>();
  final Completer<void> secondGate = Completer<void>();
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];
  bool hangSecond = false;

  @override
  String get name => 'steering';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(List<LlmMessage>.of(messages));
    if (calls.length == 1) {
      return const LlmResult(
        content: '',
        provider: 'steering',
        model: 'm',
        toolCalls: <LlmToolCall>[LlmToolCall(id: 'c1', name: 'echo')],
      );
    }
    if (hangSecond) await secondGate.future;
    return const LlmResult(content: '收口', provider: 'steering', model: 'm');
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

Future<(ConatusTuiController, Context, _SteeringProvider, Directory)> _build({
  bool hangSecond = false,
}) async {
  final Context app = Context.root();
  provideTools(app);
  final Directory dir = Directory.systemTemp.createTempSync('nava-steer-');
  app.provide('workdir', dir.path);
  final _SteeringProvider provider = _SteeringProvider()
    ..hangSecond = hangSecond;
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[provider]));
  app.tools.fn(
    'echo',
    description: '等门后回显',
    handler: (ToolContext ctx) async {
      await provider.toolGate.future;
      return ToolResult.success('ok');
    },
  );
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    storyEnabled: true,
    onExit: () {},
  );
  await controller.start();
  return (controller, app, provider, dir);
}

/// 轮询直到 [cond] 成立（超时上限 2s）。
Future<void> _until(bool Function() cond) async {
  for (int i = 0; i < 400 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(cond(), isTrue, reason: '条件未在超时内成立');
}

void main() {
  test('busy 时排队的消息在下一次请求边界注入，队列清空、轮末不重复发送', () async {
    final (controller, app, provider, _) = await _build();
    addTearDown(app.dispose);

    final Future<void> first = controller.handleLine('开始干活');
    await _until(() => provider.calls.isNotEmpty && controller.busy);

    await controller.handleLine('中途插话');
    expect(controller.queuedCount, 1);
    provider.toolGate.complete(); // 放行工具 → step 1 边界注入
    await _until(() => provider.calls.length >= 2);

    // 第二次请求的消息序列：tool 结果之后跟着注入的 user 插话。
    final List<LlmMessage> second = provider.calls[1];
    expect(second.last.role, 'user');
    expect(second.last.content, '中途插话');
    expect(second[second.length - 2].role, 'tool');
    expect(controller.queuedCount, 0);

    await first;
    await _until(() => !controller.busy);
    // 轮末 _drainQueue 对空队列无操作：模型调用总数停在 2，不重复发送。
    expect(provider.calls.length, 2);
  });

  test('Esc 打断时已注入的插话留在会话（说出去的话不收回）', () async {
    final (controller, app, provider, _) = await _build(hangSecond: true);
    addTearDown(app.dispose);

    final Future<void> first = controller.handleLine('开始干活');
    await _until(() => provider.calls.isNotEmpty && controller.busy);
    await controller.handleLine('插话留存');
    provider.toolGate.complete();
    await _until(() => provider.calls.length >= 2); // 已注入，第二次请求挂起

    controller.interrupt();
    await _until(() => !controller.busy);
    provider.secondGate.complete();
    await first;

    // 注入的插话作为 user 事件已上屏（会话事件在，不被打断收回）。
    expect(
      controller.transcript.messages.any(
        (TuiMessage m) => m.role == TuiRole.user && m.text == '插话留存',
      ),
      isTrue,
    );
    expect(controller.queuedCount, 0);
  });
  test('steering 合并两来源：人的编辑通报在前、排队文本在后', () async {
    final (controller, app, provider, dir) = await _build();
    addTearDown(() {
      app.dispose();
      dir.deleteSync(recursive: true);
    });

    await _settleWatcher(); // 先让 watcher 建好基线，之后的改动才算编辑
    final Future<void> first = controller.handleLine('开始干活');
    await _until(() => provider.calls.isNotEmpty && controller.busy);
    // 人在 AI 工作途中改文件（watcher 轮询登记 human 补丁 + 通报）。
    File('${dir.path}/notes.md').writeAsStringSync('人改的\n内容');
    await controller.handleLine('排队文本');
    await _settleWatcher();

    provider.toolGate.complete(); // 放行工具 → step 1 边界注入
    await _until(() => provider.calls.length >= 2);

    final List<LlmMessage> second = provider.calls[1];
    expect(second.last.role, 'user');
    expect(second.last.content, '排队文本');
    expect(second[second.length - 2].content, contains('notes.md'));
    expect(second[second.length - 2].content, contains('修改了文件'));
    expect(second[second.length - 3].role, 'tool');
    await first;
  });

  test('空闲时人改文件：通报留队列，下一轮 step 0 注入', () async {
    final (controller, app, provider, dir) = await _build();
    addTearDown(() {
      app.dispose();
      dir.deleteSync(recursive: true);
    });
    provider.toolGate.complete(); // 工具不等门，轮次可直接跑完
    await _settleWatcher(); // 先建基线

    // 空闲时人改文件 → watcher 登记通报，留在队列。
    File('${dir.path}/idle.md').writeAsStringSync('空闲时人新建');
    await _settleWatcher();
    expect(controller.busy, isFalse);

    await controller.handleLine('新任务');
    await _until(() => provider.calls.isNotEmpty);

    // 下一轮 step 0 组请求前注入：第一次请求就带通报。
    final List<LlmMessage> firstCall = provider.calls.first;
    expect(
      firstCall.any(
        (LlmMessage m) => m.role == 'user' && m.content.contains('idle.md'),
      ),
      isTrue,
    );
    await _until(() => !controller.busy);
  });
}

/// 等 watcher 至少扫过两轮（基线 + 发现改动）：轮询间隔 500ms，无外部
/// 可观测信号，只能定时等——留足余量避免 flaky。
Future<void> _settleWatcher() =>
    Future<void>.delayed(const Duration(milliseconds: 1400));

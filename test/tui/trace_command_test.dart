/// `/trace` 命令：把一轮的真实事件复盘成可读时间线。
library;

import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 先调一次工具（失败）再收口，用来造出可复盘的事件序列。
class _ScriptedProvider implements LlmProvider {
  int calls = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls++;
    return calls == 1
        ? const LlmResult(
            content: '',
            provider: 'scripted',
            model: 'm',
            toolCalls: <LlmToolCall>[
              LlmToolCall(id: 'c1', name: 'read_file'),
            ],
          )
        : const LlmResult(content: '改完了', provider: 'scripted', model: 'm');
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

Future<ConatusTuiController> _launch(Context app) async {
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    onExit: () {},
  );
  await controller.start();
  return controller;
}

void main() {
  test('复盘上一轮：输入、工具调用与结果都在', () async {
    final Context app = Context.root();
    addTearDown(app.dispose);
    provideTools(app);
    provideFileSystemLocal(app);
    provideShellLocal(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider()]));
    final ConatusTuiController controller = await _launch(app);

    await controller.handleLine('读一下文件');
    await controller.handleLine('/trace');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('你 › 读一下文件'));
    expect(text, contains('read_file'));
    expect(text, contains('助手 › 改完了'));
  });

  test('缺省只看最后一轮', () async {
    final Context app = Context.root();
    addTearDown(app.dispose);
    provideTools(app);
    provideFileSystemLocal(app);
    provideShellLocal(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider()]));
    final ConatusTuiController controller = await _launch(app);

    await controller.handleLine('第一件事');
    await controller.handleLine('第二件事');
    await controller.handleLine('/trace');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('第二件事'));
    expect(text.contains('你 › 第一件事'), isFalse);
  });

  test('/trace 2 看最近两轮', () async {
    final Context app = Context.root();
    addTearDown(app.dispose);
    provideTools(app);
    provideFileSystemLocal(app);
    provideShellLocal(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider()]));
    final ConatusTuiController controller = await _launch(app);

    await controller.handleLine('第一件事');
    await controller.handleLine('第二件事');
    await controller.handleLine('/trace 2');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('第一件事'));
    expect(text, contains('第二件事'));
  });

  test('参数不是数字时给出提示而不是静默', () async {
    final Context app = Context.root();
    addTearDown(app.dispose);
    provideTools(app);
    provideFileSystemLocal(app);
    provideShellLocal(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider()]));
    final ConatusTuiController controller = await _launch(app);

    await controller.handleLine('/trace abc');

    expect(controller.transcript.messages.last.text, contains('轮数'));
  });

  test('命令表包含 trace', () {
    expect(tuiCommands.any((TuiCommand c) => c.name == 'trace'), isTrue);
  });
}

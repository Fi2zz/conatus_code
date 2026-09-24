/// Stop hook：轮次收口时触发（真实 /bin/sh 命令写文件断言）。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
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
  }) async =>
      const LlmResult(content: '完成', provider: 'stub', model: 'm');

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

void main() {
  test('轮次收口后 Stop hook 触发', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-stop-hook');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String marker = '${dir.path}${Platform.pathSeparator}stop.txt';

    final Context app = Context.root();
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
    final SessionStore sessions = provideSessions(app);
    provideHooks(
      app,
      config: HooksConfig(stop: <String>['echo stop-fired > $marker']),
    );
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: 'test',
      modelLabel: 'mock',
      onExit: () {},
    );
    addTearDown(app.dispose);
    await controller.start();

    await controller.handleLine('跑一轮');

    expect(File(marker).existsSync(), isTrue);
    expect(File(marker).readAsStringSync().trim(), 'stop-fired');
  });

  test('Stop hook 失败只提示不打断', () async {
    final Context app = Context.root();
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
    final SessionStore sessions = provideSessions(app);
    provideHooks(app, config: const HooksConfig(stop: <String>['false']));
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: 'test',
      modelLabel: 'mock',
      onExit: () {},
    );
    addTearDown(app.dispose);
    await controller.start();

    await controller.handleLine('跑一轮');

    expect(
      controller.transcript.messages.any((TuiMessage m) =>
          m.text.contains('Stop hook 失败')),
      isTrue,
    );
  });
}

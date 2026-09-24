/// `/background` 命令：list / output / kill（不经模型）。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

import '../background/support/fake_shell.dart';

class _StubProvider implements LlmProvider {
  @override
  String get name => 'stub';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      const LlmResult(content: 'ok', provider: 'stub', model: 'm');

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

Future<(ConatusTuiController, Context)> _build({
  List<FakeShellProcess> processes = const <FakeShellProcess>[],
  bool withService = true,
}) async {
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
  final SessionStore sessions = provideSessions(app);
  if (withService) {
    final FakeBackgroundShell shell = FakeBackgroundShell(processes);
    final BackgroundTaskService service =
        BackgroundTaskService(shell: shell, maxRunningTasks: 2);
    app.provide('backgroundTasks', service);
    provideBackgroundTools(app, service: service);
  }
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
  test('/background list 空与有任务；output / kill 子命令', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      processes: <FakeShellProcess>[
        FakeShellProcess(outputs: <String>['后台输出'], killResult: true),
      ],
    );
    addTearDown(app.dispose);
    await app
        .get<BackgroundTaskService>('backgroundTasks')!
        .start('dart build');

    await controller.handleLine('/background list');
    expect(controller.transcript.messages.last.text, contains('bg-1'));
    expect(controller.transcript.messages.last.text, contains('dart build'));

    await controller.handleLine('/background output bg-1');
    expect(controller.transcript.messages.last.text, contains('后台输出'));

    await controller.handleLine('/background kill bg-1');
    expect(controller.transcript.messages.last.text, contains('已终止'));
  });

  test('未装配服务时提示不可用', () async {
    final (ConatusTuiController controller, Context app) =
        await _build(withService: false);
    addTearDown(app.dispose);

    await controller.handleLine('/background list');
    expect(controller.transcript.messages.last.text, contains('后台任务不可用'));
  });

  test('非法子命令给用法提示', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      processes: <FakeShellProcess>[FakeShellProcess()],
    );
    addTearDown(app.dispose);

    await controller.handleLine('/background foo');
    expect(controller.transcript.messages.last.text, contains('用法'));
  });
}

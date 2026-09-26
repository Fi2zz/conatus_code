/// `!` shell 模式：直接执行不经模型、`!!` 重跑、busy 拒绝、失败映射。
library;

import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

import '../fs_tools/support/fake_shell.dart';

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

ShellRunResult _run({
  int? exitCode = 0,
  bool timedOut = false,
  String stdout = '',
  String stderr = '',
}) =>
    ShellRunResult(
      exitCode: exitCode,
      timedOut: timedOut,
      timeoutMs: 60000,
      stdout: CollectedOutput(text: stdout),
      stderr: CollectedOutput(text: stderr),
    );

Future<(ConatusTuiController, Context, FakeShellExecutor)> _build(
  ShellRunResult result,
) async {
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
  final SessionStore sessions = provideSessions(app);
  final FakeShellExecutor shell = FakeShellExecutor(result);
  app.provide('shell', shell);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    onExit: () {},
  );
  await controller.start();
  return (controller, app, shell);
}

void main() {
  test('!命令 直接执行并上屏（不进模型）', () async {
    final (ConatusTuiController controller, Context app, FakeShellExecutor shell) =
        await _build(_run(stdout: 'on master'));
    addTearDown(app.dispose);

    await controller.handleLine('!git status');

    expect(shell.lastRequest!.command, 'git status');
    final List<String> texts = controller.transcript.messages
        .map((TuiMessage m) => m.text)
        .toList();
    expect(texts, contains('\$ git status'));
    expect(texts, contains('on master'));
    // 模型未被调用（无 user/assistant 对话消息）。
    expect(
      controller.transcript.messages
          .where((TuiMessage m) => m.role == TuiRole.user)
          .toList(),
      hasLength(0),
    );
  });

  test("'shellInteractive' 存在时 bang 走交互缝（'shell' 沙箱缝零调用）", () async {
    final (ConatusTuiController controller, Context app, FakeShellExecutor shell) =
        await _build(_run(stdout: 'sandbox-out'));
    addTearDown(app.dispose);
    final FakeShellExecutor interactive =
        FakeShellExecutor(_run(stdout: 'local-out'));
    app.provide('shellInteractive', interactive);

    await controller.handleLine('!which kimi');

    expect(interactive.lastRequest!.command, 'which kimi');
    expect(interactive.calls, 1);
    // 沙箱缝完全未被触碰：交互命令不过模型命令白名单。
    expect(shell.calls, 0);
    expect(
      controller.transcript.messages
          .any((TuiMessage m) => m.text == 'local-out'),
      isTrue,
    );
  });

  test('!! 重跑上一条；无历史提示', () async {
    final (ConatusTuiController controller, Context app, FakeShellExecutor shell) =
        await _build(_run(stdout: 'ok'));
    addTearDown(app.dispose);

    await controller.handleLine('!echo 第一');
    expect(shell.lastRequest!.command, 'echo 第一');

    await controller.handleLine('!!');
    expect(shell.lastRequest!.command, 'echo 第一');
    expect(
      controller.transcript.messages.any(
          (TuiMessage m) => m.text == r'$ echo 第一'),
      isTrue,
    );
  });

  test('! 空输入给用法；!! 无历史提示', () async {
    final (ConatusTuiController controller, Context app, _) =
        await _build(_run());
    addTearDown(app.dispose);

    await controller.handleLine('!');
    expect(controller.transcript.messages.last.text, contains('用法'));

    await controller.handleLine('!!');
    expect(controller.transcript.messages.last.text, contains('没有可重跑'));
  });

  test('执行后立刻触发重绘（结果不等下一次事件才上屏）', () async {
    final (ConatusTuiController controller, Context app, _) =
        await _build(_run(stdout: 'ok'));
    addTearDown(app.dispose);
    int refreshes = 0;
    controller.onChanged = () => refreshes++;

    await controller.handleLine('!echo hi');

    // 命令回显 + 结果各刷新一次。
    expect(refreshes, greaterThanOrEqualTo(2));
  });

  test('busy 时拒绝', () async {
    final (ConatusTuiController controller, Context app, _) =
        await _build(_run());
    addTearDown(app.dispose);

    controller.busy = true;
    await controller.handleLine('!echo hi');

    expect(controller.transcript.messages.last.text, contains('有在途轮次'));
  });

  test('失败/超时映射', () async {
    final (ConatusTuiController controller, Context app, _) =
        await _build(_run(exitCode: 1, stdout: 'out', stderr: 'boom'));
    addTearDown(app.dispose);

    await controller.handleLine('!false');

    expect(
      controller.transcript.messages.last.text,
      contains('命令失败（exit 1）'),
    );
    expect(controller.transcript.messages.last.text, contains('boom'));

    final (ConatusTuiController timedOut, Context timedApp, _) =
        await _build(_run(timedOut: true));
    addTearDown(timedApp.dispose);
    await timedOut.handleLine('!sleep 999');
    expect(timedOut.transcript.messages.last.text, contains('超时'));
  });

  test('命令未找到（exit 127）错误行原样直出，不加命令失败包装', () async {
    final (ConatusTuiController controller, Context app, _) = await _build(
        _run(exitCode: 127, stderr: 'bash: fork: command not found'));
    addTearDown(app.dispose);

    await controller.handleLine('!fork');

    expect(
      controller.transcript.messages.last.text,
      'bash: fork: command not found',
    );
  });
}

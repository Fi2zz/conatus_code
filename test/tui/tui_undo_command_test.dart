/// `/undo` `/redo`：按轮撤销（文件 + 对话）、重做、prompt 回填与提交语义。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 固定回复的假 provider。
class _ScriptedProvider implements LlmProvider {
  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async => const LlmResult(content: 'ok', provider: 'scripted', model: 'm');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

(String, String) _workspace() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-undo-tui');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String projectDir = '${dir.path}${Platform.pathSeparator}.conatus';
  Directory(projectDir).createSync();
  return (dir.path, projectDir);
}

void _write(String root, String rel, String content) {
  final File file = File('$root${Platform.pathSeparator}$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

String _read(String root, String rel) =>
    File('$root${Platform.pathSeparator}$rel').readAsStringSync();

Future<void> _disposeAfterSettle(
  Context app,
  ConatusTuiController controller,
) async {
  await controller.checkpointSettled;
  app.dispose();
}

/// 装配带 checkpointManager 的控制器（检查点配置可关 / 可限保留数）。
Future<(ConatusTuiController, Context, String)> _build({
  bool enabled = true,
  int keep = 5,
  void Function(String root)? beforeStart,
}) async {
  final (String root, String projectDir) = _workspace();
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider()]));
  final SessionStore sessions = provideSessions(app);
  app.provide(
    'checkpointManager',
    CheckpointManager(
      store: ArchiveCheckpointStore(
        root: root,
        projectDir: projectDir,
        keep: keep,
      ),
      config: CheckpointConfig(enabled: enabled, keep: keep),
    ),
  );
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    onExit: () {},
  );
  controller.confirmRevert = (String _) async => true;
  beforeStart?.call(root);
  await controller.start();
  await controller.checkpointSettled;
  return (controller, app, root);
}

/// 跑两轮：v1（第一轮）→ v2（第二轮）。
Future<void> _twoTurns(ConatusTuiController controller, String root) async {
  _write(root, 'a.txt', 'v1');
  await controller.handleLine('第一轮');
  _write(root, 'a.txt', 'v2');
  await controller.handleLine('第二轮');
}

List<String> _texts(ConatusTuiController controller) => <String>[
  for (final TuiMessage message in controller.transcript.messages) message.text,
];

void main() {
  test('/undo 恢复文件、分叉对话并回填最新 prompt', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);
    final String original = controller.sessionId;

    await controller.handleLine('/undo');

    expect(_read(root, 'a.txt'), 'v1');
    expect(controller.sessionId, isNot(original));
    expect(controller.takePrefillInput(), contains('第二轮'));
    final List<String> texts = _texts(controller);
    expect(texts.any((String t) => t.contains('已撤销')), isTrue);
    expect(texts.any((String t) => t.contains('第 1 轮')), isTrue);
  });

  test('/undo 多轮回填最新一条并提示其余', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);

    await controller.handleLine('/undo 2');

    expect(_read(root, 'a.txt'), 'v0');
    expect(controller.takePrefillInput(), contains('第二轮'));
    expect(
      _texts(controller).any((String t) => t.contains('另有 1 条')),
      isTrue,
      reason: 'N>1 时要说明其它被撤回的 prompt 没有回填',
    );
  });

  test('/redo 切回原会话并恢复撤销前的文件', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);
    final String original = controller.sessionId;

    await controller.handleLine('/undo');
    await controller.handleLine('/redo');

    expect(controller.sessionId, original);
    expect(_read(root, 'a.txt'), 'v2');
    expect(controller.transcript.messages.last.text, contains('已重做'));

    await controller.handleLine('/redo');
    expect(controller.transcript.messages.last.text, contains('没有可重做'));
  });

  test('撤销后发新 prompt 即提交：/redo 不可用', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);

    await controller.handleLine('/undo');
    await controller.handleLine('新任务');

    await controller.handleLine('/redo');
    expect(controller.transcript.messages.last.text, contains('没有可重做'));
  });

  test('确认被拒绝：不动文件也不切会话', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);
    final String original = controller.sessionId;
    controller.confirmRevert = (String _) async => false;

    await controller.handleLine('/undo');

    expect(_read(root, 'a.txt'), 'v2');
    expect(controller.sessionId, original);
    expect(controller.transcript.messages.last.text, contains('已取消'));
  });

  test('checkpoint 关闭：只回滚对话并提示', () async {
    final (
      ConatusTuiController controller,
      Context app,
      String root,
    ) = await _build(
      enabled: false,
      beforeStart: (String root) => _write(root, 'a.txt', 'v0'),
    );
    addTearDown(() => _disposeAfterSettle(app, controller));
    _write(root, 'a.txt', 'v1');
    await controller.handleLine('第一轮');
    final String original = controller.sessionId;

    await controller.handleLine('/undo');

    expect(controller.sessionId, isNot(original));
    expect(_read(root, 'a.txt'), 'v1', reason: '关闭检查点时文件不动');
    expect(
      controller.transcript.messages.last.text,
      contains('checkpoint 已关闭'),
    );
  });

  test('没有可撤销的轮次：提示且不改状态', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    final String original = controller.sessionId;

    await controller.handleLine('/undo');

    expect(controller.sessionId, original);
    expect(_read(root, 'a.txt'), 'v0');
    expect(controller.transcript.messages.last.text, contains('没有可撤销'));
  });

  test('目标轮次已被裁剪：提示找不到且不动文件', () async {
    final (
      ConatusTuiController controller,
      Context app,
      String root,
    ) = await _build(
      keep: 2,
      beforeStart: (String root) => _write(root, 'a.txt', 'v0'),
    );
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);
    final String original = controller.sessionId;

    await controller.handleLine('/undo');

    expect(controller.sessionId, original);
    expect(_read(root, 'a.txt'), 'v2');
    expect(controller.transcript.messages.last.text, contains('找不到'));
  });

  test('busy 时 /undo 拒绝；switchSession 返回 false', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    final String original = controller.sessionId;
    controller.busy = true;

    await controller.handleLine('/undo');
    expect(controller.transcript.messages.last.text, contains('有在途轮次'));

    final bool switched = await controller.switchSession(
      'session_99999999-8888-7777-6666-555555555555',
    );
    expect(switched, isFalse);
    expect(controller.sessionId, original);
  });

  test('/rewind 仍可用且不产生可重做的撤销点', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);

    await controller.handleLine('/rewind 1');

    expect(_read(root, 'a.txt'), 'v1');
    await controller.handleLine('/redo');
    expect(controller.transcript.messages.last.text, contains('没有可重做'));
  });

  test('TUI 消费回填：输入框出现撤回的 prompt', () async {
    final Context app = Context.root();
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider()]));
    final SessionStore sessions = provideSessions(app);
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: '测试',
      initialSession: 'smoke',
      modelLabel: 'mock',
      onExit: () {},
    );
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await tester.pump();

      controller.prefillInput('撤回的那句话');
      controller.showSystemNotice('刷新');
      await tester.pump();

      expect(tester.terminalState, containsText('撤回的那句话'));
      expect(controller.takePrefillInput(), isNull, reason: '回填只消费一次');
    } finally {
      tester.dispose();
      controller.dispose();
      app.dispose();
    }
  });
}

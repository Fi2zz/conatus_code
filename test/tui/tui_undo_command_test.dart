/// `/undo` `/redo`：按轮撤销（文件 + 对话）、重做、prompt 回填与提交语义。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/src/checkpoint_config_adapter.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 固定回复的假 provider；记录收到的用户 prompt（断言「没跑起来」）。
class _ScriptedProvider implements LlmProvider {
  final List<String> prompts = <String>[];

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    for (final LlmMessage message in messages.reversed) {
      if (message.role == 'user') {
        prompts.add(message.content);
        break;
      }
    }
    return const LlmResult(content: 'ok', provider: 'scripted', model: 'm');
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
///
/// [autoConfirm] 为 true 时注入「总是确认」，false 时走真实的选项浮层路径。
Future<(ConatusTuiController, Context, String)> _build({
  bool enabled = true,
  int keep = 5,
  bool autoConfirm = true,
  _ScriptedProvider? provider,
  void Function(String root)? beforeStart,
}) async {
  final (String root, String projectDir) = _workspace();
  final Context app = Context.root();
  provideTools(app);
  provideLlm(
    app,
    llm: FallbackLlm(<LlmProvider>[provider ?? _ScriptedProvider()]),
  );
  final SessionStore sessions = provideSessions(app);
  final CheckpointOptions options = checkpointOptions(
    CheckpointConfig(enabled: enabled, keep: keep),
  );
  app.provide(
    'checkpointManager',
    CheckpointManager(
      store: ArchiveCheckpointStore(
        root: root,
        projectDir: projectDir,
        keep: keep,
        policy: options.policy,
      ),
      options: options,
    ),
  );
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    onExit: () {},
  );
  if (autoConfirm) {
    controller.confirmRevert = (String _) async => true;
  }
  beforeStart?.call(root);
  await controller.start();
  await controller.checkpointSettled;
  return (controller, app, root);
}

/// 轮询直到 [cond] 成立（超时上限 2s）。
Future<void> _until(bool Function() cond) async {
  for (int i = 0; i < 400 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(cond(), isTrue, reason: '条件未在超时内成立');
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
    expect(controller.takePrefillInput(), isNull, reason: '/redo 清掉待回填内容');

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

  test('8 个标签时 /undo 仍能切到分叉会话（挤掉非活跃标签）', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);
    final String original = controller.sessionId;

    // 另开 7 个会话把标签占满，再切回有历史的会话执行 /undo。
    for (int i = 0; i < 7; i++) {
      final Session extra = app.require<SessionStore>('sessions').create();
      expect(await controller.switchSession(extra.id), isTrue);
    }
    expect(controller.tabs.tabs, hasLength(8));
    expect(await controller.switchSession(original), isTrue);

    await controller.handleLine('/undo');

    expect(controller.sessionId, isNot(original));
    expect(controller.tabs.tabs, hasLength(8), reason: '系统流程挤掉一个非活跃标签');
    expect(controller.transcript.messages.last.text, contains('已撤销'));
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

  test('checkpoint 关闭且无历史：/undo 报错且不切换', () async {
    final (
      ConatusTuiController controller,
      Context app,
      String root,
    ) = await _build(
      enabled: false,
      beforeStart: (String root) => _write(root, 'a.txt', 'v0'),
    );
    addTearDown(() => _disposeAfterSettle(app, controller));
    final String original = controller.sessionId;

    await controller.handleLine('/undo');

    expect(controller.sessionId, original);
    expect(_read(root, 'a.txt'), 'v0');
    expect(controller.transcript.messages.last.text, contains('没有可撤销'));
  });

  test('checkpoint 关闭：/redo 只切回原会话（restored:false）', () async {
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

    await controller.handleLine('/redo');

    expect(controller.sessionId, original);
    expect(_read(root, 'a.txt'), 'v1', reason: '关闭检查点时 redo 不动文件');
    expect(
      controller.transcript.messages.last.text,
      contains('checkpoint 已关闭'),
    );
  });

  test('默认确认路径：选项浮层弹出并确认后回滚', () async {
    final (
      ConatusTuiController controller,
      Context app,
      String root,
    ) = await _build(
      autoConfirm: false,
      beforeStart: (String root) => _write(root, 'a.txt', 'v0'),
    );
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);

    final Future<void> pending = controller.handleLine('/undo');
    await _until(() => controller.choice.open);

    expect(controller.choice.request!.title, contains('尚未快照的外部改动'));
    controller.choice.confirm();
    await pending;

    expect(_read(root, 'a.txt'), 'v1');
    expect(controller.takePrefillInput(), contains('第二轮'));
  });

  test('撤销进行中：拒绝新 prompt 与并发 /undo，不产生半套状态', () async {
    final _ScriptedProvider provider = _ScriptedProvider();
    final (
      ConatusTuiController controller,
      Context app,
      String root,
    ) = await _build(
      provider: provider,
      beforeStart: (String root) => _write(root, 'a.txt', 'v0'),
    );
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);
    final String original = controller.sessionId;

    final Completer<void> started = Completer<void>();
    final Completer<bool> gate = Completer<bool>();
    controller.confirmRevert = (String _) {
      if (!started.isCompleted) started.complete();
      return gate.future;
    };

    final Future<void> pending = controller.handleLine('/undo');
    await _until(() => started.isCompleted);

    // 撤销在飞的整段窗口里：新 prompt 与第二次 /undo 都被拒绝。
    await controller.handleLine('插队');
    expect(controller.transcript.messages.last.text, contains('正在撤销/重做'));
    await controller.handleLine('/undo');
    expect(controller.transcript.messages.last.text, contains('正在撤销/重做'));

    gate.complete(true);
    await pending;

    expect(_read(root, 'a.txt'), 'v1');
    expect(controller.sessionId, isNot(original));
    expect(
      provider.prompts,
      isNot(contains('插队')),
      reason: '撤销期间提交的 prompt 不能跑起来',
    );
  });

  test('busy 时 /redo 拒绝，收口后仍可重做', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);
    final String original = controller.sessionId;

    await controller.handleLine('/undo');
    controller.busy = true;
    await controller.handleLine('/redo');

    expect(controller.transcript.messages.last.text, contains('有在途轮次'));
    expect(controller.sessionId, isNot(original));
    expect(_read(root, 'a.txt'), 'v1');

    controller.busy = false;
    await controller.handleLine('/redo');
    expect(controller.sessionId, original);
    expect(_read(root, 'a.txt'), 'v2');
  });

  test('/undo 参数非法：给用法提示且不改状态', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);
    final String original = controller.sessionId;

    await controller.handleLine('/undo abc');

    expect(controller.sessionId, original);
    expect(_read(root, 'a.txt'), 'v2');
    expect(controller.transcript.messages.last.text, contains('用法：/undo'));
  });

  test('busy 时 /new 不建幽灵会话', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    final String original = controller.sessionId;
    final SessionStore sessions = app.get<SessionStore>('sessions')!;
    final int before = sessions.length;
    controller.busy = true;

    await controller.newSession();

    expect(controller.sessionId, original);
    expect(sessions.length, before, reason: '被拒绝时不能留下空会话');
    expect(controller.transcript.messages.last.text, contains('有操作进行中'));
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

  test('撤销后新建文件：取消重做时保留文件，确认后才覆盖', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);

    await controller.handleLine('/undo');
    _write(root, 'notes.txt', '撤销后新建');
    controller.confirmRevert = (String _) async => false;

    await controller.handleLine('/redo');

    expect(_texts(controller).last, contains('已取消重做'));
    expect(_read(root, 'notes.txt'), '撤销后新建', reason: '取消时不能删新文件');
    expect(_read(root, 'a.txt'), 'v1', reason: '取消时不能恢复文件');

    controller.confirmRevert = (String _) async => true;
    await controller.handleLine('/redo');

    expect(_read(root, 'a.txt'), 'v2');
    expect(
      File('$root${Platform.pathSeparator}notes.txt').existsSync(),
      isFalse,
      reason: '确认后按 rsync 语义删除撤销后新建的文件',
    );
  });

  test('切会话清掉撤销点：/redo 不可用且不动文件', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(() => _disposeAfterSettle(app, controller));
    await _twoTurns(controller, root);

    await controller.handleLine('/undo');
    expect(_read(root, 'a.txt'), 'v1');

    await controller.newSession();
    await controller.handleLine('/redo');

    expect(_texts(controller).last, contains('没有可重做'));
    expect(_read(root, 'a.txt'), 'v1', reason: '别的会话里不能覆盖当前工作区');
  });
}

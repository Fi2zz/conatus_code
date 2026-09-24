/// `/rewind` 命令：工作区文件 + 对话回滚（fork 新会话 / 新空会话）。
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
  }) async =>
      const LlmResult(content: 'ok', provider: 'scripted', model: 'm');

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

/// 建 (root, projectDir) 临时目录对。
(String, String) _workspace() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-cp-tui');
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

/// 装配带 checkpointManager 的控制器。
///
/// [initialSessionId] 非空时预置一个带历史事件的会话并绑定（模拟重开会话）；
/// [beforeStart] 在 `start()`（bind → turn 0 快照）前回调，用于摆工作区文件。
Future<(ConatusTuiController, Context, String)> _build({
  String? initialSessionId,
  void Function(String root)? beforeStart,
}) async {
  final (String root, String projectDir) = _workspace();
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider()]));
  final SessionStore sessions = provideSessions(app);
  if (initialSessionId != null) {
    final Session seeded = sessions.create(id: initialSessionId);
    seeded.append('user/message', data: <String, Object?>{'text': '历史问题'});
    seeded.append('assistant/message', data: <String, Object?>{'text': '历史回答'});
  }
  app.provide(
    'checkpointManager',
    CheckpointManager(
      store: CheckpointStore(root: root, projectDir: projectDir),
      config: const CheckpointConfig(),
    ),
  );
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    initialSession: initialSessionId,
    onExit: () {},
  );
  beforeStart?.call(root);
  await controller.start();
  return (controller, app, root);
}

void main() {
  test('新会话回滚到 turn 0：文件恢复 + 切到全新空会话', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(
      beforeStart: (String root) => _write(root, 'a.txt', 'v0'),
    );
    addTearDown(app.dispose);
    final String original = controller.sessionId;
    _write(root, 'a.txt', 'v1-broken');
    await controller.handleLine('把 a.txt 改坏一点');

    await controller.handleLine('/rewind 1');

    expect(_read(root, 'a.txt'), 'v0');
    expect(controller.sessionId, isNot(original));
    expect(controller.sessionId, matches(r'^session_[0-9a-f-]+$'));
    final String text = controller.transcript.messages.last.text;
    expect(text, contains('已回滚到第 0 轮'));
    expect(text, contains('新会话'));
  });

  test('重开会话回滚到 turn 0：fork 保留既有历史（对话回滚）', () async {
    const String seededId = 'session_11111111-2222-3333-4444-555555555555';
    final (ConatusTuiController controller, Context app, String root) =
        await _build(
      initialSessionId: seededId,
      beforeStart: (String root) => _write(root, 'a.txt', 'v0'),
    );
    addTearDown(app.dispose);
    _write(root, 'a.txt', 'v1-broken');
    await controller.handleLine('改坏 a.txt'); // turn 1

    await controller.handleLine('/rewind 1');

    expect(_read(root, 'a.txt'), 'v0');
    expect(controller.sessionId, isNot(seededId));
    // 对话保留了绑定时点之前的历史（fork 种子），回滚轮之后的消息被剔除。
    final List<String> texts = controller.transcript.messages
        .map((TuiMessage m) => m.text)
        .toList();
    expect(texts.any((String t) => t.contains('历史问题')), isTrue);
    expect(texts.any((String t) => t.contains('改坏 a.txt')), isFalse);
  });

  test('enabled=false 时 /rewind 提示不可用', () async {
    final (String root, String projectDir) = _workspace();
    final Context app = Context.root();
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider()]));
    final SessionStore sessions = provideSessions(app);
    app.provide(
      'checkpointManager',
      CheckpointManager(
        store: CheckpointStore(root: root, projectDir: projectDir),
        config: const CheckpointConfig(enabled: false),
      ),
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

    await controller.handleLine('/rewind list');

    expect(controller.transcript.messages.last.text, contains('检查点不可用'));
  });

  test('busy 时 /rewind 拒绝', () async {
    final (ConatusTuiController controller, Context app, _) = await _build();
    addTearDown(app.dispose);

    controller.busy = true;
    await controller.handleLine('/rewind 1');

    expect(controller.transcript.messages.last.text, contains('有在途轮次'));
  });

  test('回滚不动 .conatus 数据目录', () async {
    final (ConatusTuiController controller, Context app, String root) =
        await _build(beforeStart: (String root) => _write(root, 'a.txt', 'v0'));
    addTearDown(app.dispose);
    _write(root, '.conatus/keep.json', 'data');
    _write(root, 'a.txt', 'v1');
    await controller.handleLine('跑一轮');

    await controller.handleLine('/rewind 1');

    expect(_read(root, '.conatus/keep.json'), 'data');
    expect(_read(root, 'a.txt'), 'v0');
  });
}

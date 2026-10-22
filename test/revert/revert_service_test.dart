/// RevertService：撤销 / 重做的文件恢复、对话分叉与 prompt 暂存。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 建临时「工作区 + 项目数据目录」。
(String, String) _workspace() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-revert');
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

/// 一次用例的装配：两轮会话 + 两轮检查点。
class _Env {
  _Env({
    required this.root,
    required this.manager,
    required this.sessions,
    required this.session,
    required this.service,
  });

  final String root;
  final CheckpointManager manager;
  final SessionStore sessions;
  final Session session;
  final RevertService service;
}

/// 摆两轮：a.txt v0 → v1（第一轮）→ v2（第二轮）。
Future<_Env> _twoTurns({bool enabled = true, int keep = 5}) async {
  final (String root, String projectDir) = _workspace();
  final CheckpointManager manager = CheckpointManager(
    store: ArchiveCheckpointStore(
      root: root,
      projectDir: projectDir,
      keep: keep,
    ),
    config: CheckpointConfig(enabled: enabled, keep: keep),
  );
  final SessionStore sessions = SessionStore();
  final Session session = sessions.create(id: 's1');
  _write(root, 'a.txt', 'v0');
  await manager.bind('s1');
  session.append(kUserMessageEvent, data: <String, Object?>{'text': '第一轮'});
  _write(root, 'a.txt', 'v1');
  await manager.recordTurn(lastEventId: session.lastEventId);
  session.append(kUserMessageEvent, data: <String, Object?>{'text': '第二轮'});
  _write(root, 'a.txt', 'v2');
  await manager.recordTurn(lastEventId: session.lastEventId);
  return _Env(
    root: root,
    manager: manager,
    sessions: sessions,
    session: session,
    service: RevertService(checkpoint: manager, sessions: sessions),
  );
}

List<String> _prompts(Session session) => <String>[
  for (final SessionEvent event in session.events)
    if (event.type == kUserMessageEvent) '${(event.data as Map)['text']}',
];

void main() {
  test('undo 恢复文件、分叉对话并暂存最新 prompt', () async {
    final _Env env = await _twoTurns();

    final UndoResult result = await env.service.undo(env.session, 1);

    expect(result.stage.toTurn, 1);
    expect(result.stage.fromTurn, 2);
    expect(result.stage.originalSessionId, 's1');
    expect(result.stage.prompt, contains('第二轮'));
    expect(result.restore.restored, greaterThan(0));
    expect(_read(env.root, 'a.txt'), 'v1');

    final Session fork = env.sessions.get(result.stage.forkSessionId)!;
    expect(fork.id, isNot('s1'));
    expect(_prompts(fork), <String>['第一轮'], reason: '被撤回的那轮 prompt 不在新会话里');
  });

  test('redo 恢复撤销前的文件（回到 fromTurn）', () async {
    final _Env env = await _twoTurns();
    final UndoResult undone = await env.service.undo(env.session, 1);

    final RedoResult redone = await env.service.redo(undone.stage);

    expect(redone.restored, isTrue);
    expect(_read(env.root, 'a.txt'), 'v2');
  });

  test('checkpoint 关闭：只分叉对话，不动文件', () async {
    final _Env env = await _twoTurns(enabled: false);

    final UndoResult result = await env.service.undo(env.session, 1);

    expect(result.restore.restored, 0);
    expect(result.restore.deleted, 0);
    expect(_read(env.root, 'a.txt'), 'v2', reason: '关闭检查点时不碰工作区');
    final Session fork = env.sessions.get(result.stage.forkSessionId)!;
    expect(_prompts(fork), <String>['第一轮']);
    expect(result.stage.prompt, contains('第二轮'));
  });

  test('没有可撤销的轮次：报错且不改会话与文件', () async {
    final (String root, String projectDir) = _workspace();
    final CheckpointManager manager = CheckpointManager(
      store: ArchiveCheckpointStore(root: root, projectDir: projectDir),
      config: const CheckpointConfig(),
    );
    final SessionStore sessions = SessionStore();
    final Session session = sessions.create(id: 's1');
    _write(root, 'a.txt', 'v0');
    await manager.bind('s1');
    final RevertService service = RevertService(
      checkpoint: manager,
      sessions: sessions,
    );

    await expectLater(
      service.undo(session, 1),
      throwsA(
        isA<RevertException>().having(
          (RevertException e) => e.message,
          'message',
          contains('没有可撤销'),
        ),
      ),
    );
    expect(sessions.length, 1, reason: '失败时不新建会话');
    expect(_read(root, 'a.txt'), 'v0');
  });

  test('目标轮次已被裁剪：报错且不动文件', () async {
    final _Env env = await _twoTurns(keep: 2);
    expect(env.manager.list().map((CheckpointInfo i) => i.turn), <int>[0, 2]);

    await expectLater(
      env.service.undo(env.session, 1),
      throwsA(
        isA<RevertException>().having(
          (RevertException e) => e.message,
          'message',
          contains('找不到'),
        ),
      ),
    );
    expect(_read(env.root, 'a.txt'), 'v2');
    expect(env.manager.sessionId, 's1');
  });

  test('undo 多轮：回填最近一条 prompt，对话回到更早切点', () async {
    final _Env env = await _twoTurns();

    final UndoResult result = await env.service.undo(env.session, 2);

    expect(result.stage.toTurn, 0);
    expect(result.stage.prompt, contains('第二轮'), reason: '回填最新一条被撤回的 prompt');
    expect(_read(env.root, 'a.txt'), 'v0');
    final Session fork = env.sessions.get(result.stage.forkSessionId)!;
    expect(_prompts(fork), isEmpty);
  });
}

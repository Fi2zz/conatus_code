/// 会话面板：标题展示（含旧会话派生）、`r` 重命名与 `d` 删除。
library;

import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'session_rename_fixture.dart';

/// 等异步删除 / 刷新落地（面板按键处理是 unawaited 的）。
Future<void> _eventually(NoctermTester tester, bool Function() done) async {
  for (int i = 0; i < 200; i++) {
    if (done()) return;
    await tester.pump(const Duration(milliseconds: 5));
  }
  fail('条件在超时前未满足');
}

void main() {
  test('旧会话无标题：派生首条用户消息 40 字符且不写回', () async {
    final RenameFixture fix = await buildRenameFixture();

    await fix.controller.openPicker();

    final TuiSessionInfo info = fix.controller.picker.list.firstWhere(
      (TuiSessionInfo item) => item.id == renameOtherId,
    );
    expect(info.title, hasLength(40));
    expect(info.title, startsWith('Legacy question that is'));
    expect(info.updatedAt, isNotNull);
    expect(
      fix.jsonl(renameOtherId).readAsStringSync(),
      isNot(contains(kSessionTitleEvent)),
    );
  });

  test('已有标题事件时优先展示标题', () async {
    final RenameFixture fix = await buildRenameFixture();
    final Session other = await fix.sessions.open(renameOtherId);
    other.rename('Own title');
    await fix.sessions.flush();

    await fix.controller.openPicker();

    final TuiSessionInfo info = fix.controller.picker.list.firstWhere(
      (TuiSessionInfo item) => item.id == renameOtherId,
    );
    expect(info.title, 'Own title');
  });

  test('损坏的 JSONL 只影响该行，不拖垮整个面板', () async {
    final RenameFixture fix = await buildRenameFixture();
    const String corruptId = 'session_corrupt';
    fix.jsonl(corruptId).writeAsStringSync('{"seq":0,"type":"user/message"');

    await fix.controller.openPicker();

    final TuiSessionInfo corrupt = fix.controller.picker.list.firstWhere(
      (TuiSessionInfo item) => item.id == corruptId,
    );
    expect(corrupt.title, isNull);
    expect(corrupt.events, 0);
    expect(corrupt.updatedAt, isNull);
    expect(
      fix.controller.picker.list.any(
        (TuiSessionInfo item) => item.id == renameOtherId && item.title != null,
      ),
      isTrue,
      reason: '其它会话仍正常显示',
    );
    expect(fix.controller.transcript.messages.last.text, contains(corruptId));
  });

  test('picker 里按 r 打开重命名输入框并预填；Esc 取消不写会话', () async {
    final RenameFixture fix = await buildRenameFixture(start: false);
    final NoctermTester tester = await NoctermTester.create();
    addTearDown(tester.dispose);
    await tester.pumpComponent(AgentTui(controller: fix.controller));
    await _eventually(tester, () => fix.controller.ready);
    await fix.controller.openPicker();
    await tester.pump();

    await tester.sendKeyEvent(const KeyboardEvent(logicalKey: LogicalKey.keyR));
    await tester.pump();

    expect(fix.controller.renamePrompt.open, isTrue);
    expect(fix.controller.renamePrompt.targetId, fix.controller.sessionId);
    expect(fix.controller.renamePrompt.text, equals(''));

    final int before = fix.controller.session!.events.length;
    await tester.sendEscape();
    await tester.pump();

    expect(fix.controller.renamePrompt.open, isFalse);
    expect(fix.controller.picker.open, isTrue, reason: 'Esc 只关输入框');
    expect(fix.controller.session!.events, hasLength(before));
    expect(fix.controller.session!.title, isNull);
  });

  test('rename prompt 里 Enter 提交：面板行同步新标题且保留选中项', () async {
    final RenameFixture fix = await buildRenameFixture(start: false);
    final NoctermTester tester = await NoctermTester.create();
    addTearDown(tester.dispose);
    await tester.pumpComponent(AgentTui(controller: fix.controller));
    await _eventually(tester, () => fix.controller.ready);
    await fix.controller.openPicker();
    await tester.pump();
    fix.controller.movePicker(
      fix.controller.picker.list.indexWhere(
            (TuiSessionInfo item) => item.id == renameOtherId,
          ) -
          fix.controller.picker.index,
    );

    await tester.sendKeyEvent(const KeyboardEvent(logicalKey: LogicalKey.keyR));
    await tester.pump();
    expect(fix.controller.renamePrompt.open, isTrue);
    await tester.enterText('Panel rename');
    await tester.pump();
    await tester.sendKeyEvent(
      const KeyboardEvent(logicalKey: LogicalKey.enter),
    );
    await _eventually(
      tester,
      () =>
          !fix.controller.renamePrompt.open &&
          fix.sessions.get(renameOtherId)?.title == 'Panel rename' &&
          fix.controller.picker.list
                  .firstWhere((TuiSessionInfo item) => item.id == renameOtherId)
                  .title ==
              'Panel rename',
    );

    expect(fix.controller.picker.open, isTrue);
    expect(fix.controller.picker.selectedId(), renameOtherId);
    expect(
      fix.controller.picker.list
          .firstWhere((TuiSessionInfo item) => item.id == renameOtherId)
          .title,
      'Panel rename',
      reason: '面板行不能停留在旧标题',
    );
  });

  test('picker 里按 d 二次确认后删除选中会话', () async {
    final RenameFixture fix = await buildRenameFixture(start: false);
    fix.controller.confirmDelete = (String id) async => id == renameOtherId;
    final NoctermTester tester = await NoctermTester.create();
    addTearDown(tester.dispose);
    await tester.pumpComponent(AgentTui(controller: fix.controller));
    await _eventually(tester, () => fix.controller.ready);
    await fix.controller.openPicker();
    await tester.pump();
    fix.controller.movePicker(
      fix.controller.picker.list.indexWhere(
            (TuiSessionInfo item) => item.id == renameOtherId,
          ) -
          fix.controller.picker.index,
    );
    expect(fix.controller.picker.selectedId(), renameOtherId);

    await tester.sendKeyEvent(const KeyboardEvent(logicalKey: LogicalKey.keyD));
    await _eventually(
      tester,
      () =>
          !fix.jsonl(renameOtherId).existsSync() &&
          fix.controller.picker.list.every(
            (TuiSessionInfo item) => item.id != renameOtherId,
          ),
    );

    expect(fix.jsonl(renameOtherId).existsSync(), isFalse);
    expect(
      fix.controller.picker.list.any(
        (TuiSessionInfo item) => item.id == renameOtherId,
      ),
      isFalse,
      reason: '删除后刷新面板',
    );
    expect(fix.controller.sessionId, renameCurrentId);
  });
}

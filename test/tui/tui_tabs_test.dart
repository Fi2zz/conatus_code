/// 会话 tabs 与控制器 / 键位的联动：新建、复用、关闭、busy 与损坏会话。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

import 'session_rename_fixture.dart';

/// 等异步切换 / 刷新落地。
Future<void> _eventually(NoctermTester tester, bool Function() done) async {
  for (int i = 0; i < 200; i++) {
    if (done()) return;
    await tester.pump(const Duration(milliseconds: 5));
  }
  fail('条件在超时前未满足');
}

void main() {
  test('启动时只开一个标签，标题取会话标题', () async {
    final RenameFixture fix = await buildRenameFixture();

    expect(fix.controller.tabs.tabs, hasLength(1));
    expect(fix.controller.tabs.active, 0);
    expect(fix.controller.tabs.tabs.single.sessionId, renameCurrentId);
    expect(fix.controller.tabs.tabs.single.title, '当前会话的问题');
  });

  test('/new 打开新会话并追加标签，不覆盖原标签', () async {
    final RenameFixture fix = await buildRenameFixture();
    final String original = fix.controller.sessionId;

    await fix.controller.handleLine('/new');

    expect(fix.controller.tabs.tabs, hasLength(2));
    expect(fix.controller.tabs.active, 1);
    expect(fix.controller.tabs.tabs[0].sessionId, original);
    expect(fix.controller.tabs.tabs[1].sessionId, fix.controller.sessionId);
    expect(fix.controller.sessionId, isNot(original));
  });

  test('会话面板选中已打开会话时复用标签', () async {
    final RenameFixture fix = await buildRenameFixture();
    await fix.controller.handleLine('/new');
    expect(fix.controller.tabs.tabs, hasLength(2));

    await fix.controller.openPicker();
    fix.controller.movePicker(
      fix.controller.picker.list.indexWhere(
            (TuiSessionInfo item) => item.id == renameCurrentId,
          ) -
          fix.controller.picker.index,
    );
    await fix.controller.pickSelected();

    expect(fix.controller.sessionId, renameCurrentId);
    expect(fix.controller.tabs.tabs, hasLength(2));
    expect(fix.controller.tabs.active, 0);
  });

  test('busy 时拒绝切标签与关闭活跃标签并提示', () async {
    final RenameFixture fix = await buildRenameFixture();
    await fix.controller.handleLine('/new');
    final String activeId = fix.controller.sessionId;
    expect(fix.controller.tabs.active, 1);
    fix.controller.busy = true;

    expect(await fix.controller.activateNextTab(), isFalse);
    expect(fix.controller.sessionId, activeId);
    expect(fix.controller.tabs.active, 1);
    expect(fix.controller.transcript.messages.last.text, contains('有在途轮次'));

    expect(await fix.controller.closeActiveTab(), isFalse);
    expect(fix.controller.tabs.tabs, hasLength(2));
    expect(fix.controller.transcript.messages.last.text, contains('有在途轮次'));

    fix.controller.busy = false;
  });

  test('关闭标签只移除视图态，不删除会话数据', () async {
    final RenameFixture fix = await buildRenameFixture();
    await fix.controller.handleLine('/new');
    final String activeId = fix.controller.sessionId;

    expect(await fix.controller.closeTab(0), isTrue);

    expect(fix.controller.tabs.tabs, hasLength(1));
    expect(fix.controller.tabs.tabs.single.sessionId, activeId);
    expect(fix.sessions.get(renameCurrentId), isNotNull);
    expect(fix.jsonl(renameCurrentId).existsSync(), isTrue);
  });

  test('删除非活跃会话时同步移除它的标签', () async {
    final RenameFixture fix = await buildRenameFixture();
    await fix.controller.handleLine('/new');
    expect(fix.controller.tabs.tabs, hasLength(2));

    expect(await fix.controller.deleteSession(renameCurrentId), isTrue);

    expect(fix.controller.tabs.tabs, hasLength(1));
    expect(fix.controller.tabs.tabs.single.sessionId, fix.controller.sessionId);
    expect(fix.controller.tabs.active, 0);
  });

  test('关闭活跃标签切到邻居；关闭最后一个标签开新会话', () async {
    final RenameFixture fix = await buildRenameFixture();
    final String original = fix.controller.sessionId;
    await fix.controller.handleLine('/new');

    expect(await fix.controller.closeActiveTab(), isTrue);
    expect(fix.controller.sessionId, original);
    expect(fix.controller.tabs.active, 0);

    expect(await fix.controller.closeActiveTab(), isTrue);
    expect(fix.controller.tabs.tabs, hasLength(1));
    expect(fix.controller.sessionId, isNot(original));
    expect(fix.controller.ready, isTrue);
    expect(fix.sessions.get(original), isNotNull);
  });

  test('损坏会话读取失败：提示且保持在原会话', () async {
    final RenameFixture fix = await buildRenameFixture();
    const String corruptId = 'session_corrupt_tab';
    fix.jsonl(corruptId).writeAsStringSync('{"seq":0,"type":"user/message"');
    final String original = fix.controller.sessionId;

    expect(await fix.controller.switchSession(corruptId), isFalse);

    expect(fix.controller.sessionId, original);
    expect(fix.controller.ready, isTrue);
    expect(fix.controller.tabs.tabs.single.sessionId, original);
    expect(fix.controller.transcript.messages.last.text, contains('读取失败'));
  });

  test('tab 栏渲染标题、活跃标记与容量提示', () async {
    final RenameFixture fix = await buildRenameFixture(start: false);
    final NoctermTester tester = await NoctermTester.create();
    addTearDown(tester.dispose);
    await tester.pumpComponent(AgentTui(controller: fix.controller));
    await _eventually(tester, () => fix.controller.ready);
    await fix.controller.renameSession(renameCurrentId, 'TabTitleOne');
    await tester.pump();

    expect(tester.terminalState, containsText('TabTitleOne'));
    expect(tester.terminalState, containsText('1/8'));
    expect(tester.terminalState, containsText('▸'));
    expect(tester.terminalState, containsText('+'));
    expect(tester.terminalState, containsText('<leader>w'));

    await fix.controller.handleLine('/new');
    await tester.pump();
    expect(fix.controller.tabs.tabs, hasLength(2));
    expect(tester.terminalState, containsText('2/8'));
  });

  test('Ctrl+Tab / Ctrl+Shift+Tab / <leader>w 通过键位动作切换与关闭', () async {
    final RenameFixture fix = await buildRenameFixture(start: false);
    final NoctermTester tester = await NoctermTester.create();
    addTearDown(tester.dispose);
    await tester.pumpComponent(AgentTui(controller: fix.controller));
    await _eventually(tester, () => fix.controller.ready);
    await fix.controller.handleLine('/new');
    await tester.pump();
    expect(fix.controller.tabs.active, 1);

    await tester.sendKeyEvent(
      const KeyboardEvent(
        logicalKey: LogicalKey.tab,
        modifiers: ModifierKeys(ctrl: true),
      ),
    );
    await _eventually(tester, () => fix.controller.tabs.active == 0);
    expect(fix.controller.sessionId, renameCurrentId);

    await tester.sendKeyEvent(
      const KeyboardEvent(
        logicalKey: LogicalKey.tab,
        modifiers: ModifierKeys(ctrl: true, shift: true),
      ),
    );
    await _eventually(tester, () => fix.controller.tabs.active == 1);

    await tester.sendKeyEvent(
      const KeyboardEvent(
        logicalKey: LogicalKey.keyX,
        modifiers: ModifierKeys(ctrl: true),
      ),
    );
    await tester.sendKeyEvent(const KeyboardEvent(logicalKey: LogicalKey.keyW));
    await _eventually(tester, () => fix.controller.tabs.tabs.length == 1);
    expect(fix.controller.tabs.active, 0);
  });
}

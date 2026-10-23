/// `/rename` 与删除：JSONL / 检查点 / 故事线清理。
library;

import 'dart:io';

import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'session_rename_fixture.dart';

void main() {
  test('/rename <标题> 直接改当前会话标题', () async {
    final RenameFixture fix = await buildRenameFixture();

    await fix.controller.handleLine('/rename Auth cleanup');

    expect(fix.controller.session!.title, 'Auth cleanup');
    expect(
      fix.controller.transcript.messages.last.text,
      contains('Auth cleanup'),
    );
  });

  test('/rename 无参打开输入框并预填；取消不写会话', () async {
    final RenameFixture fix = await buildRenameFixture();
    await fix.controller.handleLine('/rename First title');
    final List<SessionEvent> before = fix.controller.session!.events;

    await fix.controller.handleLine('/rename');

    expect(fix.controller.renamePrompt.open, isTrue);
    expect(fix.controller.renamePrompt.targetId, renameCurrentId);
    expect(fix.controller.renamePrompt.text, 'First title');

    fix.controller.renamePrompt.close();
    expect(fix.controller.renamePrompt.open, isFalse);
    expect(fix.controller.session!.events, hasLength(before.length));
    expect(fix.controller.session!.title, 'First title');
  });

  test('提交输入框只改一次标题', () async {
    final RenameFixture fix = await buildRenameFixture();
    fix.controller.renamePrompt.show(renameCurrentId, null);
    fix.controller.renamePrompt.input.text = 'Renamed by prompt';

    expect(await fix.controller.commitRename(), isTrue);

    expect(fix.controller.session!.title, 'Renamed by prompt');
    expect(fix.controller.renamePrompt.open, isFalse);
    expect(
      fix.controller.session!.events.where(
        (SessionEvent e) => e.type == kSessionTitleEvent,
      ),
      hasLength(1),
    );
  });

  test('空白标题提交：保持输入框打开且不写会话', () async {
    final RenameFixture fix = await buildRenameFixture();
    fix.controller.renamePrompt.show(renameCurrentId, null);
    fix.controller.renamePrompt.input.text = '   ';

    expect(await fix.controller.commitRename(), isFalse);

    expect(fix.controller.renamePrompt.open, isTrue);
    expect(fix.controller.session!.title, isNull);
    expect(
      fix.controller.session!.events.where(
        (SessionEvent e) => e.type == kSessionTitleEvent,
      ),
      isEmpty,
    );
  });

  test('重命名未知会话：拒绝且不创建标题-only 文件', () async {
    final RenameFixture fix = await buildRenameFixture();

    expect(
      await fix.controller.renameSession('session_missing', 'Nope'),
      isFalse,
    );
    expect(fix.jsonl('session_missing').existsSync(), isFalse);
  });

  test('删除：拒绝当前会话，其他会话清 JSONL / 检查点 / 故事线', () async {
    final RenameFixture fix = await buildRenameFixture();
    final File currentFile = fix.jsonl(renameCurrentId);
    final File otherFile = fix.jsonl(renameOtherId);
    Directory(
      fix.checkpointSessionDir(renameOtherId),
    ).createSync(recursive: true);
    await fix.storyLog.append(
      SessionEvent.create(sessionId: renameOtherId, type: 'doc/note', seq: 0),
    );
    expect(currentFile.existsSync(), isTrue);
    expect(otherFile.existsSync(), isTrue);

    expect(await fix.controller.deleteSession(renameCurrentId), isFalse);
    expect(currentFile.existsSync(), isTrue, reason: '当前会话必须保留');

    expect(await fix.controller.deleteSession(renameOtherId), isTrue);
    expect(otherFile.existsSync(), isFalse);
    expect(
      Directory(fix.checkpointSessionDir(renameOtherId)).existsSync(),
      isFalse,
    );
    expect(await fix.storyLog.list(), isNot(contains(renameOtherId)));
    expect(currentFile.existsSync(), isTrue);
    expect(fix.controller.sessionId, renameCurrentId);
  });

  test('未知会话删除返回 false', () async {
    final RenameFixture fix = await buildRenameFixture();

    expect(await fix.controller.deleteSession('session_missing'), isFalse);
  });

  test('真实二次确认：默认取消，切到删除后清会话', () async {
    final RenameFixture fix = await buildRenameFixture();
    await fix.controller.openPicker();
    fix.controller.movePicker(
      fix.controller.picker.list.indexWhere(
            (TuiSessionInfo item) => item.id == renameOtherId,
          ) -
          fix.controller.picker.index,
    );

    final Future<void> pending = fix.controller.deleteSelectedSession();
    expect(fix.controller.choice.open, isTrue);
    expect(fix.controller.choice.request!.title, contains(renameOtherId));

    fix.controller.choice.move(-1);
    fix.controller.choice.confirm();
    await pending;

    expect(fix.jsonl(renameOtherId).existsSync(), isFalse);
  });

  test('d 落在当前会话：不弹确认，直接拒绝', () async {
    final RenameFixture fix = await buildRenameFixture();
    int confirmations = 0;
    fix.controller.confirmDelete = (String _) async {
      confirmations++;
      return true;
    };
    await fix.controller.openPicker();
    expect(fix.controller.picker.selectedId(), renameCurrentId);

    await fix.controller.deleteSelectedSession();

    expect(confirmations, 0);
    expect(fix.jsonl(renameCurrentId).existsSync(), isTrue);
    expect(fix.controller.transcript.messages.last.text, contains('不能删除当前会话'));
  });
}

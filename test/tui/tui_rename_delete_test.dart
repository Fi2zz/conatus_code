/// `/rename` 与删除：JSONL / 检查点 / 故事线清理。
library;

import 'dart:io';

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
      fix.controller.session!.events
          .where((SessionEvent e) => e.type == kSessionTitleEvent),
      hasLength(1),
    );
  });

  test('删除：拒绝当前会话，其他会话清 JSONL / 检查点 / 故事线', () async {
    final RenameFixture fix = await buildRenameFixture();
    final File currentFile = fix.jsonl(renameCurrentId);
    final File otherFile = fix.jsonl(renameOtherId);
    Directory(fix.checkpointSessionDir(renameOtherId)).createSync(
      recursive: true,
    );
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
}

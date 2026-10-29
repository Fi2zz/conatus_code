/// 控制器：输入历史导航与会话切换时的 UI 状态恢复。
library;

import 'dart:io';

import 'package:conatus_code/src/tui/session_ui_state.dart';
import 'package:test/test.dart';

import 'session_rename_fixture.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-ui-ctrl');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void main() {
  test('提交输入后 ↑ / ↓ 可前后浏览，末尾回到草稿', () async {
    final RenameFixture fix = await buildRenameFixture();
    await fix.controller.handleLine('第一句');
    await fix.controller.handleLine('第二句');

    expect(fix.controller.previousInput('草稿'), '第二句');
    expect(fix.controller.previousInput(''), '第一句');
    expect(fix.controller.previousInput(''), '第一句');
    expect(fix.controller.nextInput(), '第二句');
    expect(fix.controller.nextInput(), '草稿');
    expect(fix.controller.nextInput(), isNull);
  });

  test('切换会话再回来恢复滚动位置与输入历史', () async {
    final SessionUiStateStore store = SessionUiStateStore(dir: _tempDir().path);
    final RenameFixture fix = await buildRenameFixture(uiState: store);
    await fix.controller.handleLine('当前会话的输入');
    fix.controller.recordScroll(42.5);
    double? restored;
    fix.controller.onTabRestore = (double offset) => restored = offset;

    await fix.controller.switchSession(renameOtherId);
    await fix.controller.switchSession(renameCurrentId);

    expect(restored, 42.5);
    expect(fix.controller.previousInput(''), '当前会话的输入');
  });
}

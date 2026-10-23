/// 视图层的滚动保存/恢复接线：真实滚动偏移 → 标签 → 切换后恢复。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

import '../tui/session_rename_fixture.dart';

/// 等异步挂载 / 切换落地。
Future<void> _eventually(NoctermTester tester, bool Function() done) async {
  for (int i = 0; i < 200; i++) {
    if (done()) return;
    await tester.pump(const Duration(milliseconds: 5));
  }
  fail('条件在超时前未满足');
}

void main() {
  test('视图注入滚动保存/恢复：老标签回原偏移，新标签到末尾', () async {
    final RenameFixture fix = await buildRenameFixture(start: false);
    final NoctermTester tester = await NoctermTester.create();
    addTearDown(tester.dispose);
    await tester.pumpComponent(AgentTui(controller: fix.controller));
    await _eventually(tester, () => fix.controller.ready);
    expect(fix.controller.onTabLeave, isNotNull);
    expect(fix.controller.onTabRestore, isNotNull);

    // 撑满聊天区，让自动滚动把偏移推到非零。
    for (int i = 0; i < 40; i++) {
      fix.controller.transcript.add(TuiRole.system, 'line $i');
    }
    fix.controller.onChanged?.call();
    await tester.pump();
    await tester.pump();
    fix.controller.onTabLeave!();
    expect(fix.controller.tabs.restoreScroll(), greaterThan(0));

    double? restored;
    fix.controller.onTabRestore = (double offset) => restored = offset;
    // 首次打开 B：没有保存过偏移 → 恢复到 double.infinity（视图 clamp 到末尾）。
    await fix.controller.switchSession(renameOtherId);
    expect(restored, double.infinity);

    fix.controller.onTabLeave!();
    await fix.controller.switchSession(renameCurrentId);
    expect(restored, greaterThan(0));
  });
}

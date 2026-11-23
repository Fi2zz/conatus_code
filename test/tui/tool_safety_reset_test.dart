import 'package:conatus_code/safety.dart';
import 'package:test/test.dart';

import 'session_rename_fixture.dart';

void main() {
  test('切换会话清空读台账', () async {
    final RenameFixture fix = await buildRenameFixture();
    provideToolSafety(fix.app, workdir: fix.sessionsDir.parent.path);
    final ToolSafety safety = fix.app.require<ToolSafety>('toolSafety');
    safety.ledger.note('/x', 'v');
    expect(await fix.controller.switchSession(renameOtherId), isTrue);
    expect(safety.ledger.length, 0);
  });

  test('rebind 同一会话不清空台账', () async {
    final RenameFixture fix = await buildRenameFixture();
    provideToolSafety(fix.app, workdir: fix.sessionsDir.parent.path);
    final ToolSafety safety = fix.app.require<ToolSafety>('toolSafety');
    safety.ledger.note('/x', 'v');
    expect(await fix.controller.rebind(), isTrue);
    expect(safety.ledger.length, 1);
  });
}

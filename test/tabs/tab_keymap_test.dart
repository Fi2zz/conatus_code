/// 标签相关键位的默认绑定：tab.next / tab.previous / tab.close。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

KeyboardEvent _tab({bool shift = false}) => KeyboardEvent(
  logicalKey: LogicalKey.tab,
  modifiers: ModifierKeys(ctrl: true, shift: shift),
);

void main() {
  test('默认键位表包含 tab.next / tab.previous / tab.close', () {
    final Keymap keymap = Keymap.fromConfig(const <String, String>{});

    expect(keymap.actionFor(_tab()), KeyActions.tabNext);
    expect(keymap.actionFor(_tab(shift: true)), KeyActions.tabPrevious);
    expect(keymap.labelsFor(KeyActions.tabClose), <String>['<leader>w']);
  });
}

/// 标签栏渲染：关闭键位被禁用时不留下悬空分隔符。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

void main() {
  test('关闭键位为空时不渲染多余分隔符', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(80, 8),
    );
    addTearDown(tester.dispose);
    final TabManager tabs = TabManager()..open('session_one', title: 'Alpha');

    await tester.pumpComponent(
      TabBar(tabs: tabs.tabs, active: 0, closeHint: ''),
    );

    expect(tester.terminalState, containsText('ctrl+tab 切换)'));
    expect(tester.terminalState, isNot(containsText('· 关闭')));
  });

  test('切换提示来自 keymap 而不是硬编码', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(80, 8),
    );
    addTearDown(tester.dispose);
    final TabManager tabs = TabManager()..open('session_one', title: 'Alpha');

    await tester.pumpComponent(
      TabBar(
        tabs: tabs.tabs,
        active: 0,
        nextHint: '<leader>]',
      ),
    );

    expect(tester.terminalState, containsText('<leader>] 切换'));
    expect(tester.terminalState, containsText('<leader>w 关闭'));
  });
}

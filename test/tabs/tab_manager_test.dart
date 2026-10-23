/// 会话标签视图态：打开 / 激活 / 关闭、滚动位置与容量上限。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

void main() {
  test('打开、激活与重复打开同一会话', () {
    final TabManager tabs = TabManager();

    tabs.open('s1');
    tabs.open('s2', title: '第二个');
    expect(tabs.tabs.map((SessionTab tab) => tab.sessionId), <String>[
      's1',
      's2',
    ]);
    expect(tabs.active, 1);
    expect(tabs.tabs[1].title, '第二个');

    tabs.activate(0);
    expect(tabs.active, 0);

    // 重复打开只激活并更新标题，不新增标签。
    tabs.open('s2', title: '改过的标题');
    expect(tabs.tabs, hasLength(2));
    expect(tabs.active, 1);
    expect(tabs.tabs[1].title, '改过的标题');
  });

  test('关闭非活跃标签保持当前会话；关闭活跃标签切到邻居', () {
    final TabManager tabs = TabManager()
      ..open('s1')
      ..open('s2')
      ..open('s3')
      ..activate(1);

    tabs.close(0);
    expect(tabs.tabs.map((SessionTab tab) => tab.sessionId), <String>[
      's2',
      's3',
    ]);
    expect(tabs.active, 0);
    expect(tabs.tabs[tabs.active].sessionId, 's2');

    tabs.close(0);
    expect(tabs.active, 0);
    expect(tabs.tabs[tabs.active].sessionId, 's3');
  });

  test('关闭最后一个标签后回到空态', () {
    final TabManager tabs = TabManager()..open('s1');

    tabs.close(0);

    expect(tabs.tabs, isEmpty);
    expect(tabs.active, -1);
    expect(tabs.restoreScroll(), 0);
  });

  test('tabs keep scroll offsets per session', () {
    final TabManager tabs = TabManager();
    tabs.open('s1');
    expect(tabs.activeScrollSaved, isFalse);
    tabs.saveScroll(120);
    expect(tabs.activeScrollSaved, isTrue);
    tabs.open('s2');
    tabs.saveScroll(40);
    tabs.activate(0);

    expect(tabs.restoreScroll(), 120);
    tabs.activate(1);
    expect(tabs.restoreScroll(), 40);
  });

  test('最多 8 个标签，满了不再新增也不抢走活跃位置', () {
    final TabManager tabs = TabManager();
    for (int i = 1; i <= 8; i++) {
      tabs.open('s$i');
    }
    expect(tabs.tabs, hasLength(8));
    expect(tabs.canAdd, isFalse);
    tabs.activate(3);

    tabs.open('s9');

    expect(tabs.tabs, hasLength(8));
    expect(tabs.canAdd, isFalse);
    expect(tabs.active, 3);
  });
}

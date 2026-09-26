/// 底部状态栏三段布局与上下文用量格式化。
library;

import 'dart:io';

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

void main() {
  group('formatContextUsage', () {
    test('已知窗口：ctx 299k/1M (30%)', () {
      expect(formatContextUsage(299000, 1000000), 'ctx 299k/1M (30%)');
    });

    test('未知窗口：只显示估算值', () {
      expect(formatContextUsage(4500, 0), 'ctx 5k');
      expect(formatContextUsage(500, 0), 'ctx 500t');
    });

    test('百分比钳制在 0-100', () {
      expect(formatContextUsage(2, 1), 'ctx 2t/1t (100%)');
      expect(formatContextUsage(0, 1000), 'ctx 0t/1k (0%)');
    });
  });

  group('resolveWorkspaceLocation', () {
    test('git 仓库内返回目录 + 分支，HOME 缩写为 ~', () {
      final String? home = Platform.environment['HOME'];
      final String path = Directory.current.path;
      final bool underHome = home != null && path.startsWith('$home/');

      final Future<String> future = resolveWorkspaceLocation();
      expect(future, completion(isNotEmpty));
      expect(future, completion(underHome ? startsWith('~/') : anything));
      // conatus_code 是 git 仓库：应带分支名。
      expect(future, completion(contains('master')));
    });
  });

  test('状态栏三段：权限+模型 / 提示 / 位置+上下文', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(140, 24),
    );
    addTearDown(tester.dispose);
    await tester.pumpComponent(
      const TuiStatusBar(
        pickerOpen: false,
        busy: false,
        tick: 0,
        modelLabel: 'doubao-seed-x',
        permissionLabel: 'ask_when_needed',
        location: '~/REPO/conatus master',
        contextText: 'ctx 299k/1M (30%)',
      ),
    );
    await tester.pump();

    expect(
      tester.terminalState,
      containsText('ask_when_needed   doubao-seed-x'),
    );
    expect(tester.terminalState, containsText('~/REPO/conatus master'));
    expect(tester.terminalState, containsText('ctx 299k/1M (30%)'));
    expect(tester.terminalState, containsText('回车发送'));
  });

  test('状态栏缺省：无权限/位置/上下文时不显示对应段', () async {
    final NoctermTester tester = await NoctermTester.create();
    addTearDown(tester.dispose);
    await tester.pumpComponent(
      const TuiStatusBar(
        pickerOpen: false,
        busy: false,
        tick: 0,
        modelLabel: 'mock',
      ),
    );
    await tester.pump();

    expect(tester.terminalState, containsText('mock'));
    expect(tester.terminalState, isNot(containsText('权限：')));
    expect(tester.terminalState, isNot(containsText('ctx ')));
  });
}

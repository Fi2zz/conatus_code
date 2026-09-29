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
    // 自建临时仓库断言，不依赖调用者处于什么 git 状态。此前这个用例硬编码
    // 'master' 且隐式用 Directory.current —— 换个 checkout 形态（比如 CI 用
    // `clone --recurse-submodules`，子模块落在**游离 HEAD**）就红，而生产代码
    // 其实是对的：游离 HEAD 本来就不该显示分支。
    late Directory repo;

    setUp(() {
      repo = Directory.systemTemp.createTempSync('nava-loc');
      addTearDown(() => repo.deleteSync(recursive: true));
    });

    void git(String args) {
      final ProcessResult r =
          Process.runSync('git', args.split(' '), workingDirectory: repo.path);
      expect(r.exitCode, 0, reason: 'git $args 失败：${r.stderr}');
    }

    test('有分支时返回「目录 + 分支」', () async {
      git('init -q -b main');
      git('config user.email t@example.com');
      git('config user.name t');
      File('${repo.path}${Platform.pathSeparator}a.txt').writeAsStringSync('x');
      git('add a.txt');
      git('commit -qm init');
      git('checkout -qb feature/x');

      expect(await resolveWorkspaceLocation(cwd: repo.path),
          '${repo.path} feature/x');
    });

    test('游离 HEAD：只显示目录，不显示 HEAD', () async {
      git('init -q -b main');
      git('config user.email t@example.com');
      git('config user.name t');
      File('${repo.path}${Platform.pathSeparator}a.txt').writeAsStringSync('x');
      git('add a.txt');
      git('commit -qm init');
      final String sha = (Process.runSync(
              'git', <String>['rev-parse', 'HEAD'],
              workingDirectory: repo.path)
          .stdout as String)
          .trim();
      git('checkout -q $sha');

      expect(await resolveWorkspaceLocation(cwd: repo.path), repo.path);
    });

    test('非 git 目录：只显示目录', () async {
      expect(await resolveWorkspaceLocation(cwd: repo.path), repo.path);
    });

    test('HOME 下的路径缩写成 ~', () async {
      final String? home = Platform.environment['HOME'];
      if (home == null) return; // 无 HOME 环境下跳过这条。
      final Directory under = Directory('$home/.nava-test-tmp')
        ..createSync(recursive: true);
      addTearDown(() => under.deleteSync(recursive: true));

      expect(await resolveWorkspaceLocation(cwd: under.path), startsWith('~/'));
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

  // 回归：退出确认挂起时提示（20 列）比默认提示长，此前 `showHint` 只按固定 12
  // 列判断放得下，且中段被 Spacer + Expanded 两个 flex:1 各分一半，于是提示被裁成
  // 「再按一次 Ct」并与右段撞在一起。窄终端下提示优先于环境信息。
  test('窄终端：退出确认提示完整显示，必要时舍右段', () async {
    final NoctermTester tester = await NoctermTester.create();
    addTearDown(tester.dispose);
    await tester.pumpComponent(
      const TuiStatusBar(
        pickerOpen: false,
        busy: false,
        tick: 0,
        exitPending: true,
        modelLabel: 'mock',
        permissionLabel: 'Ask When Needed',
        location: '~/REPO/conatus master',
        contextText: 'ctx ~4t',
      ),
    );
    await tester.pump();

    expect(tester.terminalState, containsText('再按一次 Ctrl+C 退出'));
    expect(tester.terminalState, containsText('Ask When Needed   mock'));
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

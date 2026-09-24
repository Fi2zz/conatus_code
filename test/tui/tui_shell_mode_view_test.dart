/// shell 模式 UI：`!` 前缀 + 占位提示 / 状态栏操作键。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

void main() {
  test('输入栏：普通模式 `> ` + 默认占位', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(80, 12),
    );
    addTearDown(tester.dispose);
    await tester.pumpComponent(
      TuiInputBar(
        controller: TextEditingController(),
        focused: true,
        busy: false,
        onSubmitted: (_) {},
      ),
    );
    await tester.pump();

    expect(tester.terminalState, containsText('> '));
    expect(tester.terminalState, containsText('/help'));
    expect(tester.terminalState, isNot(containsText(shellInputPlaceholder())));
  });

  test('输入栏：shell 模式 `! ` 前缀 + shell 占位 + 紫色边框', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(80, 12),
    );
    addTearDown(tester.dispose);
    await tester.pumpComponent(
      TuiInputBar(
        controller: TextEditingController(),
        focused: true,
        busy: false,
        shellMode: true,
        onSubmitted: (_) {},
      ),
    );
    await tester.pump();

    expect(tester.terminalState, containsText('! '));
    expect(tester.terminalState, containsText(shellInputPlaceholder()));
    expect(tester.terminalState.getCellAt(0, 0)!.style.color, Colors.magenta);
  });

  test('输入栏：普通模式边框保持蓝色', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(80, 12),
    );
    addTearDown(tester.dispose);
    await tester.pumpComponent(
      TuiInputBar(
        controller: TextEditingController(),
        focused: true,
        busy: false,
        onSubmitted: (_) {},
      ),
    );
    await tester.pump();

    expect(tester.terminalState.getCellAt(0, 0)!.style.color, Colors.blue);
  });

  test('状态栏：shell 模式显示 shell 操作提示', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(120, 12),
    );
    addTearDown(tester.dispose);
    await tester.pumpComponent(
      const TuiStatusBar(
        pickerOpen: false,
        busy: false,
        tick: 0,
        modelLabel: 'mock',
        shellMode: true,
      ),
    );
    await tester.pump();

    expect(tester.terminalState, containsText('shell 模式'));
    expect(tester.terminalState, containsText('[Esc] 退出'));
  });
}

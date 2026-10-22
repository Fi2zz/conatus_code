/// 输入框多行：Shift+Enter / Ctrl+J 插入换行，Enter 仍然提交。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

void main() {
  test('Shift+Enter 在输入框内换行，Enter 提交整段文本', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(80, 20),
    );
    addTearDown(tester.dispose);
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);
    final List<String> submitted = <String>[];

    await tester.pumpComponent(
      TuiInputBar(
        controller: controller,
        focused: true,
        busy: false,
        onSubmitted: submitted.add,
      ),
    );
    await tester.pump();

    await tester.enterText('第一行');
    await tester.sendKeyEvent(
      const KeyboardEvent(
        logicalKey: LogicalKey.enter,
        modifiers: ModifierKeys(shift: true),
      ),
    );
    await tester.enterText('第二行');
    await tester.pump();

    expect(controller.text, '第一行\n第二行');
    expect(submitted, isEmpty);

    await tester.sendKeyEvent(
      const KeyboardEvent(logicalKey: LogicalKey.enter),
    );
    expect(submitted, <String>['第一行\n第二行']);
  });

  test('Ctrl+J 是通用换行兜底', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(80, 20),
    );
    addTearDown(tester.dispose);
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpComponent(
      TuiInputBar(
        controller: controller,
        focused: true,
        busy: false,
        onSubmitted: (_) {},
      ),
    );
    await tester.pump();

    await tester.enterText('A');
    await tester.sendKeyEvent(
      const KeyboardEvent(
        logicalKey: LogicalKey.keyJ,
        modifiers: ModifierKeys(ctrl: true),
      ),
    );
    await tester.enterText('B');
    await tester.pump();

    expect(controller.text, 'A\nB');
  });
}

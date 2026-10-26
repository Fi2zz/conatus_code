/// 生成期间输入框保持可编辑：回车排队、占位显示排队反馈、状态栏保留
/// 「思考中」动画。控制器侧的队列行为由 tui_message_queue_test.dart 覆盖。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

void main() {
  test('busy 时输入框可输入、回车触发提交（排队）', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(80, 12),
    );
    addTearDown(tester.dispose);
    final List<String> submitted = <String>[];
    await tester.pumpComponent(
      TuiInputBar(
        controller: TextEditingController(),
        focused: true,
        busy: true,
        onSubmitted: submitted.add,
      ),
    );
    await tester.pump();

    await tester.enterText('排队这条');
    await tester.pump();
    expect(tester.terminalState, containsText('排队这条'));

    await tester.sendKeyEvent(
      const KeyboardEvent(logicalKey: LogicalKey.enter),
    );
    expect(submitted, <String>['排队这条']);
  });

  test('busy 且无排队：占位提示可继续输入', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(80, 12),
    );
    addTearDown(tester.dispose);
    await tester.pumpComponent(
      TuiInputBar(
        controller: TextEditingController(),
        focused: true,
        busy: true,
        onSubmitted: (_) {},
      ),
    );
    await tester.pump();

    expect(tester.terminalState, containsText('回车排队'));
  });

  test('busy 且有排队：占位显示已排队条数', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(80, 12),
    );
    addTearDown(tester.dispose);
    await tester.pumpComponent(
      TuiInputBar(
        controller: TextEditingController(),
        focused: true,
        busy: true,
        queuedCount: 2,
        onSubmitted: (_) {},
      ),
    );
    await tester.pump();

    expect(tester.terminalState, containsText('已排队 2 条'));
  });

  test('busy 时「运行中」动画保留在状态栏（不阻塞输入）', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(120, 12),
    );
    addTearDown(tester.dispose);
    await tester.pumpComponent(
      const TuiStatusBar(
        pickerOpen: false,
        busy: true,
        tick: 0,
        modelLabel: 'mock',
      ),
    );
    await tester.pump();

    expect(tester.terminalState, containsText('运行中'));
  });
}

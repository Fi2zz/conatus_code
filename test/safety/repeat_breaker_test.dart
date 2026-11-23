import 'package:conatus_code/safety.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _CountingTool extends Tool {
  int runs = 0;

  @override
  String get name => 'probe';

  @override
  String get description => '计数用测试工具';

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    runs++;
    return ToolResult.success('ok');
  }
}

void main() {
  const ToolCall call = ToolCall(
    name: 'probe',
    arguments: <String, Object?>{'a': 1, 'b': 2},
  );

  test('3 次告警、5 次拒绝，不同调用清零', () async {
    final _CountingTool tool = _CountingTool();
    final ToolRegistry tools = ToolRegistry()..register(tool);
    final RepeatTracker tracker = RepeatTracker();
    tools.guard(tracker.check);
    tools.use(RepeatWarning(tracker: tracker).call);

    for (int i = 0; i < 2; i++) {
      final ToolResult r = await tools.call(call);
      expect(r.isError, isFalse);
      expect(r.content, isNot(contains('repeat-breaker')));
    }
    final ToolResult third = await tools.call(call);
    expect(third.content, contains('repeat-breaker'));
    expect(tool.runs, 3);

    final ToolResult fourth = await tools.call(call);
    expect(fourth.content, contains('repeat-breaker'));
    final ToolResult fifth = await tools.call(call);
    expect(fifth.isError, isTrue);
    expect(fifth.content, startsWith('REPEAT_CALL_BLOCKED'));
    expect(tool.runs, 4);

    await tools.call(
      const ToolCall(name: 'probe', arguments: <String, Object?>{'a': 9}),
    );
    expect(tracker.count, 1);
  });

  test('参数键顺序不影响签名', () {
    final RepeatTracker tracker = RepeatTracker();
    expect(
      tracker.check(
        const ToolCall(
          name: 'probe',
          arguments: <String, Object?>{'a': 1, 'b': 2},
        ),
      ),
      isNull,
    );
    expect(
      tracker.check(
        const ToolCall(
          name: 'probe',
          arguments: <String, Object?>{'b': 2, 'a': 1},
        ),
      ),
      isNull,
    );
    expect(tracker.count, 2);
  });

  test('豁免工具不计数', () {
    final RepeatTracker tracker = RepeatTracker(
      exemptTools: const <String>{'bash'},
    );
    for (int i = 0; i < 6; i++) {
      expect(
        tracker.check(
          const ToolCall(
            name: 'bash',
            arguments: <String, Object?>{'command': 'ls'},
          ),
        ),
        isNull,
      );
    }
  });

  test('阈值 0 关闭对应行为', () async {
    final _CountingTool tool = _CountingTool();
    final ToolRegistry tools = ToolRegistry()..register(tool);
    final RepeatTracker tracker = RepeatTracker(warnAt: 0, denyAt: 0);
    tools.guard(tracker.check);
    tools.use(RepeatWarning(tracker: tracker).call);
    for (int i = 0; i < 6; i++) {
      final ToolResult r = await tools.call(call);
      expect(r.isError, isFalse);
      expect(r.content, isNot(contains('repeat-breaker')));
    }
  });

  test('签名是 64 位且不同参数不同', () {
    final String a = callSignature(
      const ToolCall(name: 'probe', arguments: <String, Object?>{'a': 1}),
    );
    final String b = callSignature(
      const ToolCall(name: 'probe', arguments: <String, Object?>{'a': 2}),
    );
    expect(a.split('\u0000').last, hasLength(16));
    expect(a, isNot(b));
  });
}

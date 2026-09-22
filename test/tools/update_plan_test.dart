import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('UpdatePlanTool', () {
    test('无计划时提示先 plan_write', () async {
      final UpdatePlanTool tool = UpdatePlanTool(session: Session(id: 's1'));

      final ToolResult result = await tool.call(_call(<String, Object?>{
        'todos': <Object?>[<String, Object?>{'index': 1, 'done': true}],
      }));

      expect(result.isError, isTrue);
      expect(result.content, contains('plan_write'));
    });

    test('按 index 标记完成并改写文案', () async {
      final Session session = await _withPlan(2);
      final UpdatePlanTool tool = UpdatePlanTool(session: session);

      final ToolResult result = await tool.call(_call(<String, Object?>{
        'todos': <Object?>[
          <String, Object?>{'index': 1, 'done': true},
          <String, Object?>{'index': 2, 'text': '新文案'},
        ],
      }));

      expect(result.isError, isFalse);
      final Plan? plan = readPlan(session);
      expect(plan!.steps[0].done, isTrue);
      expect(plan.steps[1].text, '新文案');
      expect(plan.steps, hasLength(2));
      expect(session.events.last.type, kPlanEvent);
    });

    test('不带 index 的条目追加到末尾', () async {
      final Session session = await _withPlan(2);
      final UpdatePlanTool tool = UpdatePlanTool(session: session);

      final ToolResult result = await tool.call(_call(<String, Object?>{
        'todos': <Object?>[<String, Object?>{'text': '第三步'}],
      }));

      expect(result.isError, isFalse);
      final Plan? plan = readPlan(session);
      expect(plan!.steps, hasLength(3));
      expect(plan.steps[2].text, '第三步');
      expect(plan.steps[2].id, 's3');
    });

    test('更新 goal', () async {
      final Session session = await _withPlan(1);
      final UpdatePlanTool tool = UpdatePlanTool(session: session);

      final ToolResult result =
          await tool.call(_call(<String, Object?>{'goal': '新目标'}));

      expect(result.isError, isFalse);
      expect(readPlan(session)!.goal, '新目标');
    });

    test('越界 index 报部分更新未生效且计划不变', () async {
      final Session session = await _withPlan(2);
      final UpdatePlanTool tool = UpdatePlanTool(session: session);

      final ToolResult result = await tool.call(_call(<String, Object?>{
        'todos': <Object?>[<String, Object?>{'index': 9, 'done': true}],
      }));

      expect(result.isError, isTrue);
      expect(result.content, contains('越界'));
      expect(readPlan(session)!.steps, hasLength(2));
    });

    test('todos 为空且无 goal 抛参数错误', () async {
      final Session session = await _withPlan(1);
      final UpdatePlanTool tool = UpdatePlanTool(session: session);

      await expectLater(
        tool.call(_call(<String, Object?>{'todos': <Object?>[]})),
        throwsA(isA<ToolArgumentException>()),
      );
    });
  });

  test('provideUpdatePlanTool 注册 update_plan', () {
    final Context ctx = Context.root();
    provideTools(ctx);
    provideUpdatePlanTool(ctx, session: Session(id: 's1'));

    expect(ctx.tools.get('update_plan'), isNotNull);
    ctx.dispose();
  });
}

ToolContext _call(Map<String, Object?> arguments) => ToolContext(
      ToolCall(name: 'update_plan', arguments: arguments),
    );

Future<Session> _withPlan(int stepCount) async {
  final Session session = Session(id: 's1');
  final PlanTool tool = PlanTool(session: session);
  await tool.call(ToolContext(ToolCall(
    name: kPlanToolName,
    arguments: <String, Object?>{
      'goal': '测试目标',
      'steps': <Object?>[
        for (int i = 1; i <= stepCount; i++) '步骤$i',
      ],
    },
  )));
  return session;
}

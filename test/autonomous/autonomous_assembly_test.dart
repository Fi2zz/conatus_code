import 'dart:async';
import 'dart:convert';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/providers.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('装配后 autonomousRunner 可解析，costTracker 预算检查生效', () async {
    final Context ctx = Context.root();
    provideTools(ctx);
    final Session session = Session(id: 's1');
    provideLlm(ctx, llm: FallbackLlm(<LlmProvider>[_EchoProvider()]));
    provideGoal(ctx, session: session);
    // 必须给真实费率：费率未知时成本恒为 0，预算这条闸门就永远不会响
    // （旧实现靠写死的 0.3/M 才恰好触发，那是巧合而非语义）。
    final ModelProfileStore store = await _profileStore();
    final CostTrackerImpl tracker = CostTrackerImpl(
      store: store,
      provider: 'testprov',
      model: 'test-model',
    );
    ctx.provide('costTracker', tracker);
    provideAutonomous(ctx, session: session, maxSteps: 2);

    final AutonomousRunner runner = ctx.autonomousRunner;
    expect(runner, isA<DefaultAutonomousRunner>());

    // 预算已超限：首拍即 budgetExceeded，不跑任何轮（证明 runner 消费的
    // 正是根上下文注册的 CostTrackerImpl）。
    tracker.recordUsage(<String, dynamic>{'prompt_tokens': 2000000});
    expect(tracker.todayCost, greaterThan(0.1), reason: '先确认成本确实算出来了');
    runner.setPolicy(const DefaultAutonomousPolicy(dailyBudget: 0.1));
    await ctx.goal.create('盯机票');
    final AutonomousResult result = await runner.run();

    expect(result.stoppedReason, StopReason.budgetExceeded);
    expect(result.turns, isEmpty);

    ctx.dispose();
    store.close();
  });

  test('未提供 costTracker 时降级为无预算限制', () async {
    final Context ctx = Context.root();
    provideTools(ctx);
    final Session session = Session(id: 's1');
    provideLlm(ctx, llm: FallbackLlm(<LlmProvider>[_EchoProvider()]));
    provideGoal(ctx, session: session);
    provideAutonomous(ctx, session: session);

    final AutonomousRunner runner = ctx.autonomousRunner;
    final AutonomousResult result = await runner.run();

    expect(result.stoppedReason, StopReason.completed);
    expect(result.totalCost, 0);

    ctx.dispose();
  });
}

class _EchoProvider implements LlmProvider {
  @override
  String get name => 'echo';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async => const LlmResult(content: 'ok', provider: 'echo', model: 'm');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 一份只含 `testprov/test-model`（$1/M in、$3/M out）的 models.dev 档案。
Future<ModelProfileStore> _profileStore() async {
  final ModelProfileStore store = ModelProfileStore(
    client: ModelsDevClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, dynamic>{
            'testprov': <String, dynamic>{
              'models': <String, dynamic>{
                'test-model': <String, dynamic>{
                  'id': 'test-model',
                  'name': 'Test',
                  'tool_call': true,
                  'reasoning': true,
                  'limit': <String, dynamic>{'context': 200000},
                  'cost': <String, dynamic>{'input': 1.0, 'output': 3.0},
                },
              },
            },
          }),
          200,
        ),
      ),
    ),
  );
  await store.warmUp();
  return store;
}

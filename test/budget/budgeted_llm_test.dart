import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

void main() {
  group('BudgetedLlmProvider', () {
    test('预算为 0 时直接收口，不调用底层', () async {
      final _FakeProvider provider = _FakeProvider(_reply());
      final BudgetedLlmProvider budgeted = BudgetedLlmProvider(
        provider,
        budget: const TurnBudget(maxTokens: 0),
      );

      final LlmResult result =
          await budgeted.chat(<LlmMessage>[const LlmMessage('user', 'hi')]);

      expect(result.content, kBudgetExhaustedReply);
      expect(result.toolCalls, isEmpty);
      expect(provider.calls, 0);
    });

    test('墙钟超限时收口', () async {
      final _FakeProvider provider = _FakeProvider(_reply());
      final BudgetedLlmProvider budgeted = BudgetedLlmProvider(
        provider,
        budget: const TurnBudget(maxDuration: Duration.zero),
      );

      final LlmResult result =
          await budgeted.chat(<LlmMessage>[const LlmMessage('user', 'hi')]);

      expect(result.content, kBudgetExhaustedReply);
      expect(provider.calls, 0);
    });

    test('同一轮累计 token 超限后收口', () async {
      final _FakeProvider provider = _FakeProvider(_reply());
      final BudgetedLlmProvider budgeted = BudgetedLlmProvider(
        provider,
        budget: const TurnBudget(maxTokens: 20),
      );

      await budgeted.chat(<LlmMessage>[LlmMessage('user', 'a' * 40)]);
      final LlmResult second =
          await budgeted.chat(<LlmMessage>[LlmMessage('user', 'b' * 40)]);

      expect(second.content, kBudgetExhaustedReply);
      expect(provider.calls, 1);
    });

    test('空闲超过 idleReset 视为新一轮，累计清零', () async {
      final _FakeProvider provider = _FakeProvider(_reply());
      final BudgetedLlmProvider budgeted = BudgetedLlmProvider(
        provider,
        budget: const TurnBudget(maxTokens: 20),
        idleReset: const Duration(milliseconds: 20),
      );

      await budgeted.chat(<LlmMessage>[LlmMessage('user', 'a' * 40)]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final LlmResult second =
          await budgeted.chat(<LlmMessage>[LlmMessage('user', 'b' * 40)]);

      expect(second.content, isNot(kBudgetExhaustedReply));
      expect(provider.calls, 2);
    });

    test('正常调用透传结果并累计成本', () async {
      final CostTrackerImpl tracker = CostTrackerImpl();
      final _FakeProvider provider = _FakeProvider(_reply(
        usage: <String, dynamic>{
          'prompt_tokens': 1000000,
          'completion_tokens': 0,
        },
      ));
      final BudgetedLlmProvider budgeted = BudgetedLlmProvider(
        provider,
        budget: const TurnBudget(maxTokens: 1000000),
        costTracker: tracker,
      );

      final LlmResult result =
          await budgeted.chat(<LlmMessage>[const LlmMessage('user', 'hi')]);

      expect(result.content, 'ok');
      expect(result.usage['prompt_tokens'], 1000000);
      expect(provider.calls, 1);
      expect(tracker.todayCost, closeTo(kInputRatePerMillion, 1e-9));
    });

    test('chatStream 超限时只产出一个 LlmStreamDone', () async {
      final _FakeProvider provider = _FakeProvider(_reply());
      final BudgetedLlmProvider budgeted = BudgetedLlmProvider(
        provider,
        budget: const TurnBudget(maxTokens: 0),
      );

      final List<LlmStreamEvent> events = await budgeted
          .chatStream(<LlmMessage>[const LlmMessage('user', 'hi')])
          .toList();

      expect(events, hasLength(1));
      expect(events.single, isA<LlmStreamDone>());
      expect(provider.calls, 0);
    });
  });
}

LlmResult _reply({Map<String, dynamic>? usage}) => LlmResult(
      content: 'ok',
      provider: 'fake',
      model: 'fake-model',
      usage: usage ?? const <String, dynamic>{},
    );

class _FakeProvider implements LlmProvider {
  _FakeProvider(this.reply);

  final LlmResult reply;
  int calls = 0;

  @override
  String get name => 'fake';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls++;
    return reply;
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async* {
    calls++;
    yield const LlmStreamDone();
  }

  @override
  void close() {}
}

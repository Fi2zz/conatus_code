import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  group('TurnBudget', () {
    test('默认 10 分钟墙钟、20 万 token 估算', () {
      const TurnBudget budget = TurnBudget();
      expect(budget.exceededClock(const Duration(minutes: 9, seconds: 59)),
          isFalse);
      expect(budget.exceededClock(const Duration(minutes: 10, seconds: 1)),
          isTrue);
      expect(budget.exceededTokens(199999), isFalse);
      expect(budget.exceededTokens(200001), isTrue);
    });

    test('null 上限表示不限制', () {
      const TurnBudget budget =
          TurnBudget(maxDuration: null, maxTokens: null);
      expect(budget.exceededClock(const Duration(days: 1)), isFalse);
      expect(budget.exceededTokens(1 << 30), isFalse);
    });

    test('自定义上限立即生效', () {
      const TurnBudget budget =
          TurnBudget(maxDuration: Duration.zero, maxTokens: 0);
      expect(budget.exceededClock(const Duration(seconds: 1)), isTrue);
      expect(budget.exceededTokens(1), isTrue);
    });
  });
}

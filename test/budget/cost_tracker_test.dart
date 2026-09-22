import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  test('recordUsage 累计 prompt/completion token 并换算成本', () {
    final CostTrackerImpl tracker = CostTrackerImpl();
    expect(tracker.todayCost, 0);
    tracker.recordUsage(<String, dynamic>{
      'prompt_tokens': 1000000,
      'completion_tokens': 0,
    });
    expect(tracker.todayCost, closeTo(kInputRatePerMillion, 1e-9));
    tracker.recordUsage(<String, dynamic>{
      'prompt_tokens': 0,
      'completion_tokens': 500000,
    });
    expect(
      tracker.todayCost,
      closeTo(kInputRatePerMillion + kOutputRatePerMillion / 2, 1e-9),
    );
  });

  test('缺失或非数字字段按 0 处理', () {
    final CostTrackerImpl tracker = CostTrackerImpl();
    tracker.recordUsage(<String, dynamic>{});
    tracker.recordUsage(<String, dynamic>{'prompt_tokens': 'x'});
    expect(tracker.todayCost, 0);
  });
}

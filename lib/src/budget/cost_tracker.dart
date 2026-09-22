/// 首个 [CostTracker] 实现：从 LLM 用量累计当日成本（护栏口径）。
library;

import 'package:conatus_agent/conatus_agent.dart';

/// 每百万输入 token 的成本（美元）。粗略护栏口径，不用于计费。
const double kInputRatePerMillion = 0.3;

/// 每百万输出 token 的成本（美元）。粗略护栏口径，不用于计费。
const double kOutputRatePerMillion = 1.2;

/// 从用量记录累计成本的 [CostTracker]。
///
/// 进程内累计、跨日不滚动重置（实例随进程创建，接近当日口径）。消费方是
/// 未来 autonomous runner 的 `dailyBudget` 检查输入。
class CostTrackerImpl implements CostTracker {
  int _promptTokens = 0;
  int _completionTokens = 0;

  /// 记录一次用量（OpenAI 口径：`prompt_tokens` / `completion_tokens`）。
  void recordUsage(Map<String, dynamic> usage) {
    _promptTokens += _intOf(usage, 'prompt_tokens');
    _completionTokens += _intOf(usage, 'completion_tokens');
  }

  @override
  double get todayCost =>
      _promptTokens / 1000000 * kInputRatePerMillion +
      _completionTokens / 1000000 * kOutputRatePerMillion;

  static int _intOf(Map<String, dynamic> usage, String key) {
    final Object? value = usage[key];
    return value is num ? value.toInt() : 0;
  }
}

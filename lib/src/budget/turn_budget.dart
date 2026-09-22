/// 单轮预算：墙钟上限与上下文 token 估算上限（护栏口径，不用于计费）。
library;

/// 单轮预算约束。
///
/// [maxDuration] 为墙钟上限，[maxTokens] 为上下文 token 估算上限
/// （[estimateMessagesTokens] 口径，约 4 字符 1 token，只作护栏）。
/// 任一字段为 null 表示不限制。
class TurnBudget {
  const TurnBudget({
    this.maxDuration = const Duration(minutes: 10),
    this.maxTokens = 200000,
  });

  /// 单轮墙钟上限；null 表示不限。
  final Duration? maxDuration;

  /// 单轮上下文估算 token 上限；null 表示不限。
  final int? maxTokens;

  /// [elapsed] 是否达到或超过墙钟上限。
  bool exceededClock(Duration elapsed) {
    final Duration? limit = maxDuration;
    return limit != null && elapsed >= limit;
  }

  /// 累计估算 token 是否超过上限。
  bool exceededTokens(int estimated) {
    final int? limit = maxTokens;
    return limit != null && estimated > limit;
  }
}

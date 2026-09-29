/// 单轮预算：墙钟上限与上下文 token 上限（护栏口径，不用于计费）。
library;

/// 单轮预算约束。
///
/// [maxTokens] 是**用户设的上限**，而真正生效的封顶是它与「模型窗口 ×
/// [kWindowHeadroom]」的较小者（见 [effectiveTokenLimit]）。原因是模型窗口是
/// 硬约束：32k 的模型上把上限设成 200k 不但没用，还会让请求先被 API 拒掉，
/// 护栏形同虚设。配置只能让封顶更严，不能放宽到超过模型窗口。
class TurnBudget {
  const TurnBudget({
    this.maxDuration = const Duration(minutes: 10),
    this.maxTokens = 200000,
  });

  /// 上下文封顶相对模型窗口保留的比例：余下 1/4 留给模型输出与工具回填。
  static const double kWindowHeadroom = 0.75;

  /// 单轮墙钟上限；null 表示不限。
  final Duration? maxDuration;

  /// 单轮上下文 token 上限（用户配置）；null 表示不限。
  final int? maxTokens;

  /// [elapsed] 是否达到或超过墙钟上限。
  bool exceededClock(Duration elapsed) {
    final Duration? limit = maxDuration;
    return limit != null && elapsed >= limit;
  }

  /// 累计估算 token 是否超过生效封顶。
  ///
  /// [windowTokens] 是当前模型的真实上下文窗口（0 = 未知，此时只看配置）。
  bool exceededTokens(int estimated, {int windowTokens = 0}) {
    final int? limit = effectiveTokenLimit(windowTokens);
    return limit != null && estimated > limit;
  }

  /// 生效封顶：已知模型窗口时取 `窗口 × headroom` 与配置值的较小者。
  int? effectiveTokenLimit(int windowTokens) {
    if (windowTokens > 0) {
      final int derived = (windowTokens * kWindowHeadroom).round();
      final int? configured = maxTokens;
      if (configured == null || derived < configured) return derived;
    }
    return maxTokens;
  }

  /// 封顶来源的说明，供 `/doctor` 讲清「为什么是这个数」。
  String describeTokenLimit(int windowTokens) {
    final int? limit = effectiveTokenLimit(windowTokens);
    if (limit == null) return '不限';
    if (windowTokens <= 0) return '$limit（配置值；模型窗口未知）';
    if (limit == maxTokens) {
      return '$limit（配置值，严于模型窗口 ${_compact(windowTokens)}）';
    }
    return '$limit（模型窗口 ${_compact(windowTokens)} 的 '
        '${(kWindowHeadroom * 100).round()}%）';
  }

  static String _compact(int tokens) => tokens >= 1000000
      ? '${(tokens / 1000000).toStringAsFixed(tokens % 1000000 == 0 ? 0 : 1)}M'
      : '${(tokens / 1000).round()}k';
}

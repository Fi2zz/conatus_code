/// 从真实用量累计成本（`CostTracker` 首个实现）。
///
/// 与旧版的差别不只是「换成真价」，还有两处此前让这个组件**完全失效**的问题：
///
/// 1. **流式路径不记用量**。TUI 始终带 `onStream` 走 `chatStream`，而
///    `BudgetedLlmProvider.chatStream` 直接 `yield*` 透传、从不回调
///    `recordUsage`——所以 `/cost` 一直显示 $0。修在 `budgeted_llm.dart`。
/// 2. **只认 Chat Completions 的 token 键**。`type = "kimi"`（Ark / responses
///    形态）返回的是 `input_tokens` / `output_tokens`，读 `prompt_tokens` 全是 0。
///    两种形态现在都读。
///
/// 价格来自 models.dev（见 `ModelProfileStore`）。**查不到就报「费率未知」，
/// 不用写死的常数假装**——一个错的 $ 数字比没有数字更糟。
library;

import 'package:conatus_agent/conatus_agent.dart';

import '../providers/model_profile.dart';

/// 一次调用解析出的用量（两种 token 键名归一后的结果）。
class TokenUsage {
  const TokenUsage({
    this.prompt = 0,
    this.completion = 0,
    this.cachedPrompt = 0,
  });

  /// 输入 token（含缓存命中部分）。
  final int prompt;

  /// 输出 token。
  final int completion;

  /// 其中命中缓存、按折扣价计费的部分。
  final int cachedPrompt;

  /// 是否真的拿到了数字（区别于「接口返回 0」）。
  bool get known => prompt > 0 || completion > 0;

  /// 费率未知时按**全价**计的保守成本。
  double costWith(ModelProfile? profile) {
    if (profile == null || !profile.hasPricing) return 0;
    final int fresh = (prompt - cachedPrompt).clamp(0, prompt);
    return fresh / 1e6 * profile.inputPerMillion +
        cachedPrompt / 1e6 * profile.effectiveCachedRate +
        completion / 1e6 * profile.outputPerMillion;
  }

  /// 归一两种 token 键名。
  ///
  /// * Chat Completions：`prompt_tokens` / `completion_tokens`，缓存命中在
  ///   `prompt_tokens_details.cached_tokens`；
  /// * Responses：`input_tokens` / `output_tokens`，缓存在
  ///   `input_tokens_details.cached_tokens`。
  factory TokenUsage.parse(Map<String, dynamic> usage) => TokenUsage(
        prompt: _intOf(usage, 'prompt_tokens') +
            _intOf(usage, 'input_tokens'),
        completion: _intOf(usage, 'completion_tokens') +
            _intOf(usage, 'output_tokens'),
        cachedPrompt: _intOf(_tableOf(usage, 'prompt_tokens_details'),
                'cached_tokens') +
            _intOf(_tableOf(usage, 'input_tokens_details'), 'cached_tokens'),
      );

  /// 取嵌套表（`prompt_tokens_details` 等）；不存在或类型不符返回 `null`。
  static Map<String, dynamic>? _tableOf(
    Map<String, dynamic> usage,
    String key,
  ) {
    final Object? value = usage[key];
    return value is Map<String, dynamic> ? value : null;
  }

  static int _intOf(Map<String, dynamic>? table, String key) {
    final Object? value = table?[key];
    return value is num ? value.toInt() : 0;
  }
}

/// 按真实费率累计成本与 token 的 [CostTracker]。
///
/// 进程内累计、跨日不滚动重置（实例随进程创建，接近当日口径）。费率与上下文
/// 窗口经 [store] 按当前模型解析——`/model` 切模型后自动跟着换价。
class CostTrackerImpl implements CostTracker {
  CostTrackerImpl({this.store, this.provider, this.model});

  /// 模型档案来源；缺省时所有费率未知（成本恒为 0，并如实报「未知」）。
  final ModelProfileStore? store;

  /// 当前提供商名。
  String? provider;

  /// 当前模型 id。
  String? model;

  int _promptTokens = 0;
  int _completionTokens = 0;
  int _cachedTokens = 0;
  int _calls = 0;
  int _lastPromptTokens = 0;

  /// 记录一次用量（两种 token 键名都收）。
  void recordUsage(Map<String, dynamic> usage) {
    final TokenUsage parsed = TokenUsage.parse(usage);
    if (!parsed.known) return;
    _promptTokens += parsed.prompt;
    _completionTokens += parsed.completion;
    _cachedTokens += parsed.cachedPrompt;
    _lastPromptTokens = parsed.prompt;
    _calls++;
  }

  /// 当前模型的档案；查不到返回 `null`。
  ModelProfile? get profile {
    final ModelProfileStore? source = store;
    if (source == null) return null;
    return source.profileOf(provider ?? '', model ?? '');
  }

  /// 当前模型上下文窗口（token）；未知为 0。
  int get contextLength => profile?.contextLength ?? 0;

  /// 是否拿到了真实费率（否则 `/cost` 应报「未知」而不是报一个假数字）。
  bool get ratesKnown => profile?.hasPricing ?? false;

  @override
  double get todayCost => costOf(_promptTokens, _completionTokens, _cachedTokens);

  /// 按当前费率算给定用量的成本。
  double costOf(int prompt, int completion, int cached) {
    final ModelProfile? current = profile;
    if (current == null || !current.hasPricing) return 0;
    final int fresh = (prompt - cached).clamp(0, prompt);
    return fresh / 1e6 * current.inputPerMillion +
        cached / 1e6 * current.effectiveCachedRate +
        completion / 1e6 * current.outputPerMillion;
  }

  /// 累计输入 token 数（含缓存命中部分）。
  int get promptTokens => _promptTokens;

  /// 累计输出 token 数。
  int get completionTokens => _completionTokens;

  /// 累计缓存命中 token 数。
  int get cachedTokens => _cachedTokens;

  /// 记录到的调用次数（用量为 0 的失败轮次不计入）。
  int get calls => _calls;

  /// 最近一次调用的输入 token 数——**真实**值，比 chars/4 估算准得多，
  /// 用作上下文压力。
  int get lastPromptTokens => _lastPromptTokens;

  /// 是否已经拿到过一次真实用量。
  bool get hasRealUsage => _calls > 0;
}

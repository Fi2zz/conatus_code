/// 把配置里的 `provider/model` 清单装配成「重试 + 回退」链。
///
/// 链的形状是两层嵌套：
///
/// ```text
/// FallbackLlm(                     ← 换提供商
///   ├─ RetryingLlm(deepseek)       ← 同一提供商内退避重试
///   ├─ RetryingLlm(doubao)
///   └─ RetryingLlm(gpt-4o-mini)
/// )
/// ```
///
/// 顺序即优先级：先在原提供商上把可重试的失败（限流 / 5xx / 网络）退避重试
/// `max_attempts` 次，仍失败才换下一个——避免一次网络抖动就换模型，那会让
/// 回答风格在一次会话里来回跳。
library;

import 'dart:async';

import 'package:conatus_llm/conatus_llm.dart';

import 'provider_profile.dart';
import 'provider_registry.dart';

/// LLM 韧性相关的一条运行期提示。
class LlmNotice {
  const LlmNotice(this.text);

  /// 屏上直接显示的一行中文。
  final String text;

  @override
  String toString() => text;
}

/// LLM 韧性相关的运行期提示出口。
///
/// 装配期还没有 TUI（控制器是之后才建的），而「主模型限流，正在重试」这种
/// 事实如果只在轮次结束后才出现，中间那 30 秒退避在用户眼里就是卡死。
/// 装配层把事件汇到这里，控制器订阅后**实时**写进屏上记录。
class LlmNotices {
  final StreamController<LlmNotice> _events =
      StreamController<LlmNotice>.broadcast();

  /// 提示流；可多订阅（控制器之外，测试也能挂）。
  Stream<LlmNotice> get stream => _events.stream;

  /// 最近一次回退；无则 `null`（供 `/doctor` 之类的即时查询）。
  LlmFallbackEvent? lastFallback;

  /// 退避重试通报（[RetryingLlm] 的回调形态）。
  void onRetry(LlmRetryAttempt attempt) =>
      _emit(LlmNotice('· ${attempt.summary}'));

  /// 回退通报（[FallbackLlm] 的回调形态）。
  void onFallback(LlmFallbackEvent event) {
    lastFallback = event;
    _emit(LlmNotice('· ${event.fromProvider} 不可用，已切到 ${event.toProvider}'
        '（还剩 ${event.remaining} 个候选）'));
  }

  void _emit(LlmNotice notice) {
    if (_events.isClosed) return;
    _events.add(notice);
  }

  /// 释放；挂在 `'llmNotices'` 服务的生命周期上。
  void close() => _events.close();
}

/// 装配结果：链本身 + 装配期发现的问题（供 `/doctor` 展示）。
class LlmChain {
  const LlmChain({
    required this.llm,
    required this.entries,
    this.skipped = const <String, String>{},
  });

  /// 可直接挂到 `'llm'` 的服务。
  final FallbackLlm llm;

  /// 实际生效的候选（`provider/model`），按优先级。
  final List<String> entries;

  /// 被跳过的配置项 → 原因（provider 不存在 / 没有可用模型 / 重复）。
  final Map<String, String> skipped;
}

/// 按 [entries]（`provider/model`，首项为主）装配回退链。
///
/// 每个候选各包一层 [RetryingLlm]；跳不过的项记进 [LlmChain.skipped] 而不是
/// 直接失败——配了一条写错的备用模型不该让主模型都用不了。
///
/// [fallback] 为空时仍返回一个只含主模型的链（保证有重试），全空时返回
/// `null`（调用方据此提示去 `/provider` 配置）。
LlmChain? buildLlmChain(
  ProviderRegistry registry, {
  required List<String> entries,
  required RetryPolicy policy,
  LlmNotices? notices,
}) {
  final List<LlmProvider> providers = <LlmProvider>[];
  final List<String> resolved = <String>[];
  final Map<String, String> skipped = <String, String>{};
  for (final String entry in entries) {
    final String trimmed = entry.trim();
    if (trimmed.isEmpty) continue;
    if (resolved.contains(trimmed)) {
      skipped[trimmed] = '与前面的候选重复';
      continue;
    }
    final ProviderProfile? profile = _profileFor(registry, trimmed);
    if (profile == null) {
      skipped[trimmed] = '没有名为 ${trimmed.split('/').first} 的 provider';
      continue;
    }
    final String model = trimmed.substring(trimmed.indexOf('/') + 1);
    final LlmProvider? provider = registry.buildLlm(profile.name, model: model);
    if (provider == null) {
      skipped[trimmed] = '构造不出 provider（缺 base_url 或凭据）';
      continue;
    }
    providers.add(RetryingLlm(
      provider,
      policy: policy,
      onRetry: notices?.onRetry,
    ));
    resolved.add(trimmed);
  }
  if (providers.isEmpty) return null;
  return LlmChain(
    llm: FallbackLlm(providers, onFallback: notices?.onFallback),
    entries: resolved,
    skipped: skipped,
  );
}

/// `provider/model` 的 provider 部分；查不到返回 `null`。
ProviderProfile? _profileFor(ProviderRegistry registry, String entry) {
  final int slash = entry.indexOf('/');
  if (slash <= 0 || slash >= entry.length - 1) return null;
  return registry.byName(entry.substring(0, slash));
}

/// 预算化的 LLM 装饰器：每次模型调用前检查单轮墙钟与上下文 token 护栏。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_llm/conatus_llm.dart';

import 'cost_tracker.dart';
import 'turn_budget.dart';

/// 预算收口回复：模型读到后以总结收口（不含工具调用，Agent Loop 自然结束）。
const String kBudgetExhaustedReply = '（预算已达上限，本轮收口）';

/// 包一层 [TurnBudget] 护栏的 [LlmProvider]。
///
/// 轮边界用「空闲重置」近似：距上次调用超过 [idleReset] 视为新一轮，墙钟与
/// token 累计清零（避免跨轮累计误伤）。超限时不抛异常，而是返回不含工具调用的
/// 收口回复，让 Agent Loop 正常收口。
class BudgetedLlmProvider implements LlmProvider {
  BudgetedLlmProvider(
    this.base, {
    required this.budget,
    this.costTracker,
    this.idleReset = const Duration(minutes: 2),
  });

  /// 被包装的底层提供商。
  final LlmProvider base;

  /// 预算约束。
  final TurnBudget budget;

  /// 用量记录目标；非空时每次成功调用后累计成本。
  final CostTrackerImpl? costTracker;

  /// 空闲多久视为新一轮。
  final Duration idleReset;

  DateTime? _turnStart;
  int _turnTokens = 0;

  @override
  String get name => base.name;

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final LlmResult? exhausted = _exhaustedIfOver(estimateMessagesTokens(messages));
    if (exhausted != null) return exhausted;
    final LlmResult result =
        await base.chat(messages, options: options, tools: tools);
    costTracker?.recordUsage(result.usage);
    return result;
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async* {
    if (_overLimit(estimateMessagesTokens(messages))) {
      yield const LlmStreamDone();
      return;
    }
    yield* base.chatStream(messages, options: options, tools: tools);
  }

  @override
  void close() => base.close();

  /// 超限时返回收口结果；未超限返回 null（本次估算已累计）。
  LlmResult? _exhaustedIfOver(int estimated) {
    if (!_overLimit(estimated)) return null;
    return LlmResult(
      content: kBudgetExhaustedReply,
      provider: base.name,
      model: '',
    );
  }

  /// 重置新一轮并累计本次估算；超限返回 true。
  bool _overLimit(int estimated) {
    final DateTime now = DateTime.now();
    final DateTime? start = _turnStart;
    if (start == null || now.difference(start) > idleReset) {
      _turnStart = now;
      _turnTokens = 0;
    }
    _turnTokens += estimated;
    final Duration elapsed = now.difference(_turnStart!);
    return budget.exceededClock(elapsed) || budget.exceededTokens(_turnTokens);
  }
}

/// 提供预算包装的 `'llm'` 服务；[costTracker] 单独注册，不在此覆盖。
///
/// 与 [provideLlm] 的差异：`'llm'` 被 [BudgetedLlmProvider] 包装（消费方按
/// [LlmProvider] 解析，签名仍收 [FallbackLlm]）。返回释放 `'llm'` 注册的
/// [Disposer]，供 `/model` 切换时复用。
Disposer provideBudgetedLlm(
  Context ctx, {
  required FallbackLlm llm,
  required TurnBudget budget,
  CostTrackerImpl? costTracker,
}) {
  final BudgetedLlmProvider instance =
      BudgetedLlmProvider(llm, budget: budget, costTracker: costTracker);
  final Disposer disposer = ctx.provide('llm', instance);
  ctx.onDispose(instance.close);
  return disposer;
}

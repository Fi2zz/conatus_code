/// 命令审查装饰器：在任意 [ShellExecutor] 外面套一层形状审查。
///
/// 与执行位置无关——本地直执（[LocalShellExecutor]）与将来可能的远端执行器
/// 都可以套。`deny` 与「未获复核的 review」都不抛异常，而是返回正常结果
/// （与 [ShellExecutor] 的契约一致：只有基础设施故障才 reject）。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'command_policy.dart';

/// REVIEW 裁决的人工复核回调：命令与理由进，是否放行进。
///
/// 由 TUI 装配期挂上（选项浮层征询）；未接线时 REVIEW 按拒绝处理
/// （fail-closed，headless 即此形态）。回调抛错同样按拒绝处理。
typedef CommandReviewPrompter =
    Future<bool> Function(String command, String reason);

/// 执行前过策略的装饰器。
class GuardedShellExecutor implements ShellExecutor {
  GuardedShellExecutor({required this.inner, required this.policy});

  /// 实际执行者（本地或远端）。
  final ShellExecutor inner;

  /// 命令形状审查。
  final CommandPolicy policy;

  /// 人工复核回调；未接线时 review 视为拒绝。
  CommandReviewPrompter? reviewPrompter;

  @override
  ShellExecSpec resolve(ShellExecRequest request) => inner.resolve(request);

  @override
  Future<ShellRunResult> run(ShellExecSpec spec) async {
    final String? refusal = await _refusal(spec);
    if (refusal != null) return rejectedRun(refusal, spec);
    return inner.run(spec);
  }

  @override
  Future<ShellProcess> start(ShellExecSpec spec) async {
    final String? refusal = await _refusal(spec);
    if (refusal != null) return RejectedShellProcess(refusal);
    return inner.start(spec);
  }

  /// 返回拒绝理由；放行时返回 null。
  Future<String?> _refusal(ShellExecSpec spec) async {
    final CommandVerdict verdict = policy.decide(spec.command);
    if (verdict.decision == CommandDecision.allow) return null;
    if (verdict.decision == CommandDecision.deny) {
      return '命令被拒绝：${verdict.reason}';
    }
    return _reviewRefusal(spec.command, verdict.reason);
  }

  /// REVIEW 裁决：无接线或未获批都按拒绝。
  Future<String?> _reviewRefusal(String command, String reason) async {
    final CommandReviewPrompter? prompter = reviewPrompter;
    if (prompter == null) return '命令被拒绝：$reason';
    if (await _promptSafely(prompter, command, reason)) return null;
    return '命令未获人工复核通过：$reason';
  }

  /// 人工复核（回调抛错按拒绝，fail-closed）。
  Future<bool> _promptSafely(
    CommandReviewPrompter prompter,
    String command,
    String reason,
  ) async {
    try {
      return await prompter(command, reason);
    } catch (_) {
      return false;
    }
  }
}

/// 拒绝结果：不抛异常，exitCode 为 null（调用方按非零处理并看到理由）。
ShellRunResult rejectedRun(String message, ShellExecSpec spec) =>
    ShellRunResult(
      exitCode: null,
      timedOut: false,
      timeoutMs: spec.timeoutMs,
      stdout: const CollectedOutput(text: ''),
      stderr: CollectedOutput(text: message),
    );

/// 命令被拒绝时的假进程句柄：立即完成，读输出得拒绝理由。
class RejectedShellProcess implements ShellProcess {
  RejectedShellProcess(this._reason);

  final String _reason;
  bool _read = false;

  @override
  ShellProcessStatus get status => ShellProcessStatus.completed;

  @override
  int? get exitCode => null;

  @override
  Future<void> get done => Future<void>.value();

  @override
  ShellProcessRead readOutput() {
    if (_read) return const ShellProcessRead(delta: '');
    _read = true;
    return ShellProcessRead(delta: '命令被拒绝：$_reason');
  }

  @override
  bool kill() => false;
}

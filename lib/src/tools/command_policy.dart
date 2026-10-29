/// 命令形状审查：`command_shield` 语义分析 → allow / review / deny。
///
/// 只判断「这行命令的形状是否危险」，不判断路径归属（没有沙箱根可对照），
/// 也不维护可执行白名单——**这是有意的**：白名单在无沙箱后会让常见工具
/// （`npx`、`make`、`go`）被误拒，而它们本该由权限/审批层决定要不要问人。
/// 裁决的三种结果与 `ShellExecutor` 的失败语义对齐：`deny` / 未获复核的
/// `review` 都映射成「不执行 + 理由」而非异常。
library;

import 'package:command_shield/command_shield.dart' as shield;

/// 命令策略的裁决。
enum CommandDecision { allow, deny, review }

/// 一次裁决的结果：决策与理由。
class CommandVerdict {
  const CommandVerdict(this.decision, this.reason);

  final CommandDecision decision;
  final String reason;
}

/// 命令策略：仅做语义分析，供 [GuardedShellExecutor] 在本地执行前调用。
class CommandPolicy {
  CommandPolicy({shield.CommandShield? shieldImpl})
    : _shield =
          shieldImpl ??
          shield.CommandShield(defaultSyntax: shield.CommandSyntax.bash);

  final shield.CommandShield _shield;

  /// 裁决命令；[review] 表示「形状可疑，交给人工复核」。
  CommandVerdict decide(String command) {
    final shield.CommandResult result = _shield.validate(command);
    return switch (result.decision) {
      shield.CommandDecision.allow => const CommandVerdict(
        CommandDecision.allow,
        '',
      ),
      shield.CommandDecision.review => CommandVerdict(
        CommandDecision.review,
        _findingText(result),
      ),
      shield.CommandDecision.deny => CommandVerdict(
        CommandDecision.deny,
        _findingText(result),
      ),
    };
  }

  String _findingText(shield.CommandResult result) {
    if (result.findings.isEmpty) return '命令被策略拦截';
    return result.findings
        .map((shield.SecurityFinding f) => f.message)
        .join('；');
  }
}

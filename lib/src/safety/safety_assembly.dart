/// 工具层安全护栏装配：读后写 / 重复调用 / 敏感文件。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import '../config/config_schema.dart';
import 'read_ledger.dart';
import 'repeat_breaker.dart';
import 'sensitive_guard.dart';
import 'write_guard.dart';

/// 已装配的护栏状态；服务键 `'toolSafety'`。
class ToolSafety {
  ToolSafety({required this.ledger, required this.repeat});

  /// 读台账（会话级）。
  final ReadLedger ledger;

  /// 重复调用状态机（会话级）。
  final RepeatTracker repeat;

  /// 会话切换：清空台账与计数。
  void resetSession() {
    ledger.clear();
    repeat.reset();
  }
}

/// 按 [config] 把三项护栏挂到 `ctx.tools`，返回共享状态。
///
/// 守卫先于审批中间件执行；全关时不注册任何守卫/中间件，行为与未装配一致。
ToolSafety provideToolSafety(
  Context ctx, {
  required String workdir,
  String? home,
  SafetyConfig config = const SafetyConfig(),
}) {
  final ReadLedger ledger = ReadLedger();
  final RepeatTracker repeat = RepeatTracker(
    warnAt: config.repeatWarnAt,
    denyAt: config.repeatDenyAt,
    exemptTools: config.repeatExemptTools.toSet(),
  );
  final ToolSafety safety = ToolSafety(ledger: ledger, repeat: repeat);
  ctx.provide('toolSafety', safety);

  if (config.requireReadBeforeWrite) {
    final ReadBeforeWriteGuard guard = ReadBeforeWriteGuard(
      ledger: ledger,
      workdir: workdir,
      home: home,
    );
    final ReadLedgerMiddleware middleware = ReadLedgerMiddleware(
      ledger: ledger,
      workdir: workdir,
      home: home,
    );
    ctx.effect(() => ctx.tools.guard(guard.check));
    ctx.effect(() => ctx.tools.use(middleware.call, tag: 'readLedger'));
  }
  if (config.repeatWarnAt > 0 || config.repeatDenyAt > 0) {
    ctx.effect(() => ctx.tools.guard(repeat.check));
    if (config.repeatWarnAt > 0) {
      ctx.effect(
        () => ctx.tools.use(
          RepeatWarning(tracker: repeat).call,
          tag: 'repeatBreaker',
        ),
      );
    }
  }
  if (config.protectPrivateKeys ||
      config.denyDotenvWrites ||
      config.extraSensitivePaths.isNotEmpty) {
    final SensitivePathGuard guard = SensitivePathGuard(
      tools: ctx.tools,
      workdir: workdir,
      home: home,
      protectPrivateKeys: config.protectPrivateKeys,
      denyDotenvWrites: config.denyDotenvWrites,
      extraPaths: config.extraSensitivePaths.toSet(),
    );
    ctx.effect(() => ctx.tools.guard(guard.check));
  }
  return safety;
}

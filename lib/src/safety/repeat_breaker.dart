/// 重复调用熔断：连续相同 `(工具, 排序参数)` 先告警、后拒绝。
///
/// 计数是连续语义：只要出现不同调用就清零，避免误伤「读 → 改 → 再读」与
/// 轮询命令。守卫负责拒绝（同步），中间件负责在执行结果后附加告警。
library;

import 'dart:convert';

import 'package:conatus_foundation/conatus_foundation.dart';

/// 连续相同调用达到拒绝阈值。
const String kRepeatBlockedCode = 'REPEAT_CALL_BLOCKED';

/// 一次调用的稳定签名：工具名 + 参数（按键排序后哈希）。
///
/// 参数值整串参与哈希，不截断：写入内容可能很长，但只保留哈希，内存有界；
/// 截断前缀会让「前 8 KiB 相同的两次不同写入」被误判为同一调用。
String callSignature(ToolCall call) {
  final List<String> keys = call.arguments.keys.toList()..sort();
  final Map<String, Object?> ordered = <String, Object?>{
    for (final String key in keys) key: call.arguments[key],
  };
  return '${call.name}\u0000${_digest(jsonEncode(ordered))}';
}

String _digest(String value) {
  int hash = 0x811c9dc5;
  for (final int unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// 连续调用状态机。
class RepeatTracker {
  RepeatTracker({
    this.warnAt = 3,
    this.denyAt = 5,
    this.exemptTools = const <String>{},
  });

  /// 第 N 次起告警；0 关闭。
  final int warnAt;

  /// 第 N 次起拒绝；0 关闭。
  final int denyAt;

  /// 不参与计数的工具名。
  final Set<String> exemptTools;

  String? _signature;
  int _count = 0;

  /// 当前连续次数。
  int get count => _count;

  /// 当前连续签名的工具名部分；没有记录时为 `null`。
  String? get currentSignature => _signature;

  /// 守卫入口：返回拒绝理由；`null` 表示放行。
  String? check(ToolCall call) {
    if (exemptTools.contains(call.name)) {
      reset();
      return null;
    }
    final String signature = callSignature(call);
    if (signature != _signature) {
      _signature = signature;
      _count = 1;
      return null;
    }
    _count++;
    if (denyAt > 0 && _count >= denyAt) {
      return '$kRepeatBlockedCode: 连续第 $_count 次相同调用（${call.name}）；'
          '请换方法或汇报结论';
    }
    return null;
  }

  /// [call] 是否就是当前连续调用的签名。
  bool isCurrent(ToolCall call) =>
      _signature != null && _signature == callSignature(call);

  /// 清零（会话切换）。
  void reset() {
    _signature = null;
    _count = 0;
  }
}

/// 后置中间件：执行成功/失败都按计数附加告警，不改变 `isError`。
class RepeatWarning {
  RepeatWarning({required this.tracker});

  /// 共享状态机。
  final RepeatTracker tracker;

  /// 中间件入口。
  Future<ToolResult> call(
    ToolCall call,
    Future<ToolResult> Function() next,
  ) async {
    final ToolResult result = await next();
    if (tracker.warnAt <= 0) return result;
    if (!tracker.isCurrent(call)) return result;
    final int count = tracker.count;
    if (count < tracker.warnAt) return result;
    if (tracker.denyAt > 0 && count >= tracker.denyAt) return result;
    return result.withContent(
      '${result.content}\n\n[repeat-breaker] 这是连续第 $count 次完全相同的调用；'
      '请换方法或汇报结论。',
    );
  }
}

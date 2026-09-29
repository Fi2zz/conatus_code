/// 子 Agent 进度的屏上出口。
///
/// 装配期没有 TUI（控制器之后才建），而子 Agent 一次能跑几十秒——这段时间屏
/// 上如果完全静止，用户既不知道它在干什么，也不敢 `Esc` 打断。装配层把进度
/// 汇到这里，控制器订阅后写进屏上记录。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';

/// 子 Agent 的一行屏上回执。
class SubAgentLine {
  const SubAgentLine(this.text, {this.fold = true});

  /// 屏上直接显示的一行。
  final String text;

  /// 该行是否可折叠（默认收起，只留一行摘要）。
  final bool fold;

  @override
  String toString() => text;
}

/// 子 Agent 进度广播。
class SubAgentProgressStore {
  final StreamController<SubAgentLine> _lines =
      StreamController<SubAgentLine>.broadcast();

  /// 进度行；可多订阅。
  Stream<SubAgentLine> get lines => _lines.stream;

  /// 最近一次委托的收口摘要（无则 `null`）；供 `/doctor` 之类的即时查询。
  String? lastSummary;

  /// 累计跑过几次委托。
  int runs = 0;

  /// 订阅进 [SpawnAgentTool.onProgress] 的回调。
  void report(SubAgentEvent event) {
    final SubAgentLine? line = _render(event);
    if (line == null) return;
    if (!_lines.isClosed) _lines.add(line);
  }

  /// 事件 → 屏上一行；不需要上屏的返回 `null`。
  SubAgentLine? _render(SubAgentEvent event) => switch (event) {
        SubAgentStarted(:final String task) => SubAgentLine(
            '◆ 子 Agent：${_clip(task)}',
          ),
        SubAgentToolCall(:final String tool) => SubAgentLine('  → $tool'),
        SubAgentToolDone(:final String tool, :final bool failed) =>
          SubAgentLine('  ${failed ? '✗' : '✓'} $tool'),
        SubAgentRound(:final int step, :final String reply) =>
          SubAgentLine('  · 第 $step 轮 $reply'),
        SubAgentFinished(:final String status, :final int rounds,
            :final List<String> tools) =>
          _onFinished(status, rounds, tools),
      };

  SubAgentLine _onFinished(String status, int rounds, List<String> tools) {
    runs++;
    final String mark = status == 'success' ? '✓' : '✗';
    final String used = tools.isEmpty ? '' : '（${tools.join('、')}）';
    lastSummary = '$rounds 轮 $used';
    return SubAgentLine('$mark 子 Agent $status：$rounds 轮 $used');
  }

  /// 任务描述截断（首行 + 长度上限），避免一条长 prompt 刷屏。
  String _clip(String task, {int limit = 60}) {
    final String first = task.trim().split('\n').first;
    return first.length <= limit ? first : '${first.substring(0, limit)}…';
  }

  /// 释放；挂在 `'subagentProgress'` 服务的生命周期上。
  void close() => _lines.close();
}

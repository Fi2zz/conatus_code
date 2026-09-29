/// 让子 Agent 借团队成员的身份出现在泳道里。
///
/// 背景：[SpawnAgentTool]（`spawn_agent`）与 [AgentTeam] 是两套并行的多 agent
/// 机制——前者是「一次性委托」（同步 await、拿回结论、随即销毁），后者是
/// 「常驻成员」（可收发消息、可 interrupt、有任务板）。二者语义重叠但视图各
/// 有一套，于是「谁在干什么」被拆成两处。
///
/// 本文件做**视图层**的统一，不动执行层：把一次子 Agent 委托投影成一条与
/// 团队成员同形的活动流，复用同一套泳道渲染。执行层合并要动 conatus_agent
/// 与 conatus_team 的包边界，另议。
library;

import 'package:conatus_agent/conatus_agent.dart';

/// 一次子 Agent 委托在泳道里的身份。
///
/// 用 `swarm-<序号>` 作 id，与团队成员 id 不会撞（成员 id 由 team 生成）。
class SwarmMember {
  const SwarmMember({required this.id, required this.label});

  /// 泳道 key（与团队成员 id 同处一个命名空间）。
  final String id;

  /// 屏上显示的名字。
  final String label;

  /// 泳道 id 是否为子 Agent 投影而来（这些成员不在团队的成员表里）。
  bool get projected => id.startsWith(kSwarmLanePrefix);

  /// 子 Agent 泳道的前缀；团队成员 id 不会以它开头。
  static const String kSwarmLanePrefix = 'swarm-';
}

/// 泳道写入出口（可后设）。
///
/// 装配时子 Agent 的进度回调已经接上，但泳道要等控制器订阅 `AgentTeam` 之后
/// 才有地方可写——两者不同期，故出口做成可后设的，而不是在装配期判空。
class SwarmSink {
  SwarmSink();

  void Function(String laneId, String line, bool failed)? _write;

  /// 控制器接上真正的写入。
  void attach(void Function(String laneId, String line, bool failed) write) {
    _write = write;
  }

  /// 写一行；未接上时静默丢弃（早期轮次没有团队视图，不该因此报错）。
  void write(String laneId, String line, {bool failed = false}) =>
      _write?.call(laneId, line, failed);
}

/// 子 Agent 活动 → 泳道行的投影器。
///
/// 框架侧 [SubAgentEvent] 与团队侧 [TeammateActivity] 是两套词汇（前者管
/// 「一次委托」，后者管「一个常驻成员」）。这里做一次映射，让上层只面对一种
/// 渲染输入。
class SwarmProjection {
  SwarmProjection({SwarmSink? sink}) : sink = sink ?? SwarmSink();

  /// 泳道写入出口。
  final SwarmSink sink;

  /// 每条泳道行的名字缓存：laneId → 展示名。
  final Map<String, String> labels = <String, String>{};

  int _seq = 0;
  SwarmMember? _current;

  /// 当前委托对应的成员身份；无在途委托时为 `null`。
  SwarmMember? get current => _current;

  /// 累计委托次数。
  int get runs => _seq;

  /// 接进 [SpawnAgentTool.onProgress]。
  void report(SubAgentEvent event) {
    switch (event) {
      case SubAgentStarted():
        final SwarmMember member = SwarmMember(
          id: '${SwarmMember.kSwarmLanePrefix}${++_seq}',
          label: '子 Agent #$_seq',
        );
        _current = member;
        labels[member.id] = member.label;
        sink.write(member.id, '· 开始');
      case SubAgentToolCall(:final String tool):
        _emitNow('→ $tool');
      case SubAgentToolDone(:final String tool, :final bool failed):
        _emitNow('${failed ? '✗' : '✓'} $tool', failed: failed);
      case SubAgentRound(:final int step, :final String reply):
        _emitNow('· 第 $step 轮 $reply');
      case SubAgentFinished(:final String status, :final int rounds,
          :final List<String> tools):
        _emitNow(
          '${status == 'success' ? '✓' : '✗'} 收口：$rounds 轮 '
          '${tools.isEmpty ? '' : '（${tools.join('、')}）'}',
          failed: status != 'success',
        );
        _current = null;
    }
  }

  /// 当前泳道 key；无在途委托时是 `null`。
  ///
  /// 不能退回空串——那会被 [SwarmSink] 当成一个真实泳道写出去，产生一条没有
  /// 归属的孤儿行。
  String? get _lane => _current?.id;

  /// 按当前泳道写一行；无在途委托则丢弃。
  void _emitNow(String line, {bool failed = false}) {
    final String? lane = _lane;
    if (lane == null) return;
    sink.write(lane, line, failed: failed);
  }
}

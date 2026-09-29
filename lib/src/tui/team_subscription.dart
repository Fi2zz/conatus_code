/// 团队订阅：把 [AgentTeam.changes] 事件折叠成 [TeamSnapshot]，通知 UI 重绘。
///
/// UI 订阅而非轮询：任何团队变更都走同一入口重建快照，渲染组件只读快照。
///
/// 活动是高频事件（正文逐字来），不能每条都**整份**重建快照——成员表和任务
/// 板没变，重建纯属浪费。故分成两条路径：活动只更新泳道（`[MemberLaneBuilder]`
/// 就地维护），成员/任务变更才整份重建。成本是可选 seam，未注入
/// [TeamCostSource] 时恒为 0，由渲染侧决定是否展示。
library;

import 'dart:async';

import 'package:conatus_team/conatus_team.dart';

import 'team_lanes.dart';
import 'team_snapshot.dart';

/// 团队成本来源（可选 seam）。
///
/// 宿主提供 `totalCost` 后，状态栏即可显示成本；conatus_code 经 costTracker
/// 的真实费率注入。
abstract class TeamCostSource {
  /// 累计成本。
  double get totalCost;
}

/// 团队订阅。维护 [TeamSnapshot] 并通知 UI 重绘。
class TeamSubscription {
  TeamSubscription({
    required this.team,
    required this.onChanged,
    this.costSource,
  }) {
    _snapshot = _buildSnapshot();
    _subscription = team.changes.listen(_handleEvent);
  }

  /// 被订阅的团队。
  final AgentTeam team;

  /// 快照变化回调（UI 据此重绘）。
  final void Function(TeamSnapshot) onChanged;

  /// 成本来源；缺省不提供成本。
  final TeamCostSource? costSource;

  /// 泳道折叠器；活动事件只经它，不整份重建。
  final MemberLaneBuilder lanes = MemberLaneBuilder();

  /// 塞一条子 Agent 投影泳道（与团队成员共用同一张表）。
  ///
  /// 子 Agent 不在 `AgentTeam` 里，但视图层要统一，故让它也能落进泳道。
  /// 名字取投影器给的 [label]。
  void addSwarmLine(
    String laneId,
    String line, {
    bool failed = false,
    String label = '子 Agent',
  }) {
    lanes.pushSwarm(laneId, TeamActivityLine(line, failed: failed, label: label));
    _snapshot = TeamSnapshot(
      members: _snapshot.members,
      tasks: _snapshot.tasks,
      lanes: lanes.build(_active),
      totalCost: _snapshot.totalCost,
    );
    onChanged(_snapshot);
  }

  late TeamSnapshot _snapshot;
  StreamSubscription<AgentTeamEvent>? _subscription;

  /// 成员是否在跑；由非活动事件刷新，活动路径直接复用。
  Map<String, bool> _active = <String, bool>{};

  /// 最新快照。
  TeamSnapshot get snapshot => _snapshot;

  void _handleEvent(AgentTeamEvent event) {
    if (event is TeammateActed) {
      // 高频路径：正文是逐字来的，每条都整份重建成员表纯属浪费。成员表 /
      // 任务板在活动发生时不会变，原样带上。
      lanes.add(event);
      _snapshot = TeamSnapshot(
        members: _snapshot.members,
        tasks: _snapshot.tasks,
        lanes: lanes.build(_active),
        totalCost: _snapshot.totalCost,
      );
      onChanged(_snapshot);
      return;
    }
    if (event is TeamTaskChanged && event.task.assigneeId != null) {
      // 任务换了负责人：清掉旧泳道，免得旧成员名下留着不相关的活动。
      lanes.remove(event.task.assigneeId!);
    }
    _snapshot = _buildSnapshot();
    onChanged(_snapshot);
  }

  /// 整份重建：成员表 / 任务板 / 泳道一起。
  TeamSnapshot _buildSnapshot() {
    final List<Teammate> members = List<Teammate>.unmodifiable(team.members);
    _active = <String, bool>{
      for (final Teammate m in members) m.id: !m.isTerminal,
    };
    return TeamSnapshot(
      members: members,
      tasks: List<TeamTask>.unmodifiable(team.tasks),
      lanes: lanes.build(_active),
      totalCost: costSource?.totalCost ?? 0.0,
    );
  }

  /// 释放订阅（幂等）。
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

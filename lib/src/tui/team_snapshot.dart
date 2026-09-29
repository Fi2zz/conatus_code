/// 团队状态快照与 TUI 视图模式。
///
/// [TeamSnapshot] 是 UI 渲染的数据源：由 [TeamSubscription] 事件驱动重建，
/// 渲染组件只读它，不直接触达 [AgentTeam]。视图模式 [ViewMode] 表示
/// 对话视图（默认）与团队视图之间的切换。
library;

import 'package:conatus_team/conatus_team.dart';

/// 一条可渲染的活动行。
///
/// 与框架侧的 [TeammateActivityLine] 分开：快照要**按值**裁剪与重建（见
/// [kTeamLaneMaxLines]），持有引用会把整个快照的存活期绑到事件流上。
class TeamActivityLine {
  const TeamActivityLine(this.text, {this.failed = false, this.label = ''});

  /// 屏上直接显示的一行。
  final String text;

  /// 是否失败。
  final bool failed;

  /// 泳道所属的展示名；团队成员由成员表给出，故只有子 Agent 投影的行需要
  /// 自带（它们不在成员表里）。
  final String label;
}

/// 每条泳道保留的最近活动条数。
///
/// 泳道是定高视图，成员一多就只剩最后几行；留太多既看不清当下，也白占内存
/// （正文是逐字来的，长任务能堆出上万条）。
const int kTeamLaneMaxLines = 12;

/// 单个成员的近期活动（泳道数据源）。
class MemberLane {
  const MemberLane({this.lines = const <TeamActivityLine>[], this.active = false});

  /// 近期活动行（旧的已被裁掉）。
  final List<TeamActivityLine> lines;

  /// 该成员此刻是否在跑。
  final bool active;

  /// 是否有内容可渲染。
  bool get hasLines => lines.isNotEmpty;
}

/// 团队状态快照。UI 渲染的数据源。
class TeamSnapshot {
  const TeamSnapshot({
    this.members = const <Teammate>[],
    this.tasks = const <TeamTask>[],
    this.lanes = const <String, MemberLane>{},
    this.totalCost = 0.0,
  });

  /// 所有成员。
  final List<Teammate> members;

  /// 所有任务。
  final List<TeamTask> tasks;

  /// 成员 id → 近期活动泳道。
  final Map<String, MemberLane> lanes;

  /// 累计成本。
  final double totalCost;

  /// 活跃成员数（非终态）。
  int get activeMembers => members.where((m) => !m.isTerminal).length;

  /// 已完成任务数。
  int get doneTasks =>
      tasks.where((t) => t.status == TeamTaskStatus.done).length;

  /// 任务总数。
  int get totalTasks => tasks.length;

  /// 是否有活跃团队。
  bool get hasTeam => members.isNotEmpty;

  /// 可被指定成员领取的任务：pending、依赖全 done、[assigneeId] 为空或等于该成员。
  List<TeamTask> claimableBy(String teammateId) {
    final Set<String> doneIds = tasks
        .where((TeamTask t) => t.status == TeamTaskStatus.done)
        .map((TeamTask t) => t.id)
        .toSet();
    return tasks.where((TeamTask t) {
      if (t.status != TeamTaskStatus.pending) return false;
      if (t.assigneeId != null && t.assigneeId != teammateId) return false;
      return t.dependsOn.every(doneIds.contains);
    }).toList();
  }
}

/// TUI 视图模式。
enum ViewMode {
  /// 对话视图（默认）。
  chat,

  /// 团队视图。
  team,
}

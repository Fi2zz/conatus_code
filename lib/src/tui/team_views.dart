/// 团队渲染件：状态栏、成员卡片、任务行与团队视图。
///
/// 所有组件只读 [TeamSnapshot]，不触达 [AgentTeam]——状态来自订阅流，
/// 交互走斜杠命令。图标约定见 HANDOFF-12 §7.2 / §8.2 / §8.3（成员状态
/// 实际 6 态，`finished` 用 `●`、终态 `done` 用 `✓` 区分）。
library;

import 'package:conatus_team/conatus_team.dart';
import 'package:nocterm/nocterm.dart';

import '../subagent/swarm_member.dart';
import 'team_snapshot.dart';

/// 成员状态图标与文案。
(String, String) memberStatusDisplay(TeammateStatus status) {
  return switch (status) {
    TeammateStatus.idle => ('○', '空闲'),
    TeammateStatus.working => ('◐', '执行中'),
    TeammateStatus.waiting => ('◌', '等待'),
    TeammateStatus.finished => ('●', '完成'),
    TeammateStatus.done => ('✓', '已完成'),
    TeammateStatus.failed => ('✗', '失败'),
  };
}

/// 任务状态图标与文案。
(String, String) taskStatusDisplay(TeamTaskStatus status) {
  return switch (status) {
    TeamTaskStatus.pending => ('○', '待领取'),
    TeamTaskStatus.claimed => ('◐', '执行中'),
    TeamTaskStatus.done => ('✓', '完成'),
    TeamTaskStatus.failed => ('✗', '失败'),
  };
}

/// 团队状态栏。单行，显示团队概况；无团队时不渲染。
class TeamStatusBar extends StatelessComponent {
  const TeamStatusBar({
    super.key,
    required this.snapshot,
    this.showCost = false,
  });

  /// 团队快照。
  final TeamSnapshot snapshot;

  /// 是否显示成本（有成本来源时开启）。
  final bool showCost;

  @override
  Component build(BuildContext context) {
    if (!snapshot.hasTeam) {
      return const SizedBox.shrink();
    }
    final List<String> parts = <String>[
      '团队: ${snapshot.activeMembers} 成员',
      '任务: ${snapshot.doneTasks}/${snapshot.totalTasks} 完成',
      if (showCost) '成本: \$${snapshot.totalCost.toStringAsFixed(2)}',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: const BoxDecoration(
        color: Color.fromRGB(0, 20, 40),
        border: BoxBorder(top: BorderSide(color: Colors.cyan)),
      ),
      child: Row(
        children: <Component>[
          Expanded(
            child: Text(
              ' ${parts.join(' | ')}',
              style: const TextStyle(color: Colors.gray),
            ),
          ),
        ],
      ),
    );
  }
}

/// 成员卡片：图标 + 名字 + 状态，当前任务与等待原因作为缩进行。
class MemberCard extends StatelessComponent {
  const MemberCard({super.key, required this.member, required this.tasks});

  /// 成员。
  final Teammate member;

  /// 团队任务（查当前任务描述）。
  final List<TeamTask> tasks;

  @override
  Component build(BuildContext context) {
    final (String icon, String statusText) = memberStatusDisplay(member.status);
    final TeamTask? currentTask = member.currentTaskId == null
        ? null
        : tasks.where((TeamTask t) => t.id == member.currentTaskId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          Text('$icon ${member.name}  [$statusText]'),
          if (currentTask != null)
            Text(
              '  任务: ${currentTask.description}',
              style: const TextStyle(color: Colors.gray),
            ),
          if (member.status == TeammateStatus.waiting)
            const Text(
              '  等待依赖完成',
              style: TextStyle(color: Colors.gray),
            ),
        ],
      ),
    );
  }
}

/// 任务行：图标 + 描述 + 状态，负责人与依赖作为缩进行。
class TaskRow extends StatelessComponent {
  const TaskRow({super.key, required this.task, required this.members});

  /// 任务。
  final TeamTask task;

  /// 团队成员（查负责人名字）。
  final List<Teammate> members;

  @override
  Component build(BuildContext context) {
    final (String icon, String statusText) = taskStatusDisplay(task.status);
    final Teammate? assignee = task.assigneeId == null
        ? null
        : members.where((Teammate m) => m.id == task.assigneeId).firstOrNull;
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          Text('$icon ${task.description}  [$statusText]'),
          if (assignee != null)
            Text(
              '  负责: ${assignee.name}',
              style: const TextStyle(color: Colors.gray),
            ),
          if (task.dependsOn.isNotEmpty &&
              task.status == TeamTaskStatus.pending)
            Text(
              '  依赖: ${task.dependsOn.join(', ')}',
              style: const TextStyle(color: Colors.gray),
            ),
        ],
      ),
    );
  }
}

/// 成员泳道：标题行（名字 + 状态 + 当前任务）+ 最近活动。
///
/// 定高 [kTeamLaneMaxLines] 行——成员一多，泳道就得比行数更省，否则彼此挤出
/// 视野，就失去了"swarm 总览"的意义。
class MemberLaneView extends StatelessComponent {
  const MemberLaneView({
    super.key,
    required this.id,
    required this.lane,
    this.member,
  });

  /// 泳道 id（团队成员 id 或子 Agent 投影 id）。
  ///
  /// 团队成员显示成员名；子 Agent 泳道没有成员可显示，故退回 id——
  /// 它的**行**里带着投影器给的阶段描述（`→ rg` / `✓ 收口：3 轮`），
  /// 那才是有用的信息。
  final String id;

  /// 该泳道的近期活动。
  final MemberLane lane;

  /// 团队成员；子 Agent 投影的泳道为 `null`。
  final Teammate? member;

  @override
  Component build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          _header(),
          for (final TeamActivityLine line in _visible())
            _line(line),
        ],
      ),
    );
  }

  /// 泳道头：团队成员按状态着色；子 Agent 投影用自带名字。
  Component _header() {
    final Teammate? mate = member;
    if (mate == null) return _swarmHeader();
    final (String icon, String status) = memberStatusDisplay(mate.status);
    return Text(
      '$icon ${mate.name}  [$status]',
      style: TextStyle(
        color: lane.active ? Colors.cyan : Colors.gray,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  /// 子 Agent 泳道的头：没有成员状态可言，只标出它是投影来的。
  Component _swarmHeader() => Text(
        '◆ $id',
        style: TextStyle(
          color: lane.active ? Colors.cyan : Colors.gray,
          fontWeight: FontWeight.bold,
        ),
      );

  /// 泳道头：正在跑的成员亮一点，静默的用暗色。
  Component _line(TeamActivityLine line) => Text(
        '  ${line.text}',
        style: TextStyle(color: line.failed ? Colors.red : Colors.gray),
      );

  /// 只留最后 N 行，活动的最新一条永远可见。
  List<TeamActivityLine> _visible() {
    if (lane.lines.length <= kTeamLaneMaxLines) return lane.lines;
    return lane.lines.sublist(lane.lines.length - kTeamLaneMaxLines);
  }
}

/// 团队视图：每个成员一条泳道（实时活动），下接任务板。
class TeamView extends StatelessComponent {
  const TeamView({super.key, required this.snapshot});

  /// 团队快照。
  final TeamSnapshot snapshot;

  @override
  Component build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          const Text(
            '团队泳道（Esc 或 Ctrl+T 返回对话；/team interrupt <成员> 中断）',
            style: TextStyle(color: Colors.cyan),
          ),
          const SizedBox(height: 1),
          for (final Teammate member in snapshot.members)
            MemberLaneView(
              id: member.id,
              member: member,
              lane: snapshot.lanes[member.id] ?? const MemberLane(),
            ),
          // 子 Agent 投影泳道：不在成员表里，但同处一个视图。
          for (final MapEntry<String, MemberLane> e
              in snapshot.lanes.entries)
            if (e.key.startsWith(SwarmMember.kSwarmLanePrefix))
              MemberLaneView(id: e.key, lane: e.value),
          if (snapshot.tasks.isNotEmpty) ...<Component>[
            const SizedBox(height: 1),
            const Text(
              '任务板',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            for (final TeamTask task in snapshot.tasks)
              TaskRow(task: task, members: snapshot.members),
          ],
        ],
      ),
    );
  }
}

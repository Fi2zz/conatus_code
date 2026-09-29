/// 把成员活动折叠成泳道：按成员聚合、裁剪近期行。
///
/// 单独成文件是因为 [TeamSnapshot] 已经是"数据形状"而这里是"如何从事件
/// 长出数据"的策略——后者有裁剪与合并规则，混进快照类会让它变成一个
/// 既定义形状又管算法的类。
library;

import 'package:conatus_team/conatus_team.dart';

import '../subagent/swarm_member.dart';
import 'team_snapshot.dart';

/// 泳道折叠器：持泳道 id → 近期活动行，按 [kTeamLaneMaxLines] 裁剪。
///
/// 泳道有两类来源，id 共用一个命名空间（团队成员由 team 生成，子 Agent 走
/// [SwarmMember.kSwarmLanePrefix] 前缀，不会撞）：团队成员的名字由成员表给
/// 出，子 Agent 的名字由投影器自带在行上。
///
/// 正文增量是逐字来的，若每条都单独成行，一条长回答就能刷掉整个泳道；故把
/// 连续的正文**累积到同一条**里（见 [MemberLaneBuilder.push]）。
class MemberLaneBuilder {
  MemberLaneBuilder();

  final Map<String, List<TeamActivityLine>> _lines =
      <String, List<TeamActivityLine>>{};

  /// 吃进一个成员事件；非活动事件忽略。
  ///
  /// [TeammateSpawned] 也走这里——建一条空泳道，成员一出现就有地方落活动，
  /// 界面也不必等它第一次动手才知道有这个成员。
  void add(AgentTeamEvent event) {
    final String? id = switch (event) {
      TeammateActed(:final String teammateId) => teammateId,
      TeammateSpawned(:final Teammate teammate) => teammate.id,
      _ => null,
    };
    if (id == null) return;
    if (event case TeammateActed(:final TeammateActivity activity)) {
      final TeammateActivityLine line = activityLine(activity);
      push(id, TeamActivityLine(line.text, failed: line.failed));
      return;
    }
    _lines.putIfAbsent(id, () => <TeamActivityLine>[]);
  }

  /// 折成快照用的泳道表。
  Map<String, MemberLane> build(Map<String, bool> active) => <String, MemberLane>{
        for (final MapEntry<String, List<TeamActivityLine>> e
            in _lines.entries)
          e.key: MemberLane(
            lines: List<TeamActivityLine>.unmodifiable(e.value),
            active: active[e.key] ?? false,
          ),
      };

  /// 推入一行（团队成员泳道，名字由成员表给出）。
  void push(String teammateId, TeamActivityLine line) => _push(teammateId, line);

  /// 推入一行（子 Agent 投影泳道，名字自带——它们不在成员表里）。
  void pushSwarm(String laneId, TeamActivityLine line) => _push(laneId, line);

  void _push(String teammateId, TeamActivityLine line) {
    final List<TeamActivityLine> lines =
        _lines.putIfAbsent(teammateId, () => <TeamActivityLine>[]);
    if (_isText(line.text) && lines.isNotEmpty && _isText(lines.last.text)) {
      lines[lines.length - 1] = TeamActivityLine(lines.last.text + line.text);
      return;
    }
    lines.add(line);
    if (lines.length > kTeamLaneMaxLines) {
      lines.removeRange(0, lines.length - kTeamLaneMaxLines);
    }
  }

  /// 丢弃一个成员的泳道（成员被移除时）。
  void remove(String teammateId) => _lines.remove(teammateId);

  /// 清空全部。
  void clear() => _lines.clear();

  /// 看起来是不是正文行（用于决定能否合并）。
  static bool _isText(String text) => !_markers.any(text.startsWith);
}

const List<String> _markers = <String>['→', '✓', '✗', '·', '思考'];

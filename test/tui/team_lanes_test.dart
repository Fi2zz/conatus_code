/// 泳道折叠：按成员聚合、正文合并、长度裁剪。
library;

import 'dart:async';

import 'package:conatus_code/tui.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:test/test.dart';

void _act(MemberLaneBuilder b, String id, TeammateActivity a) =>
    b.add(TeammateActed(id, a));

void main() {
  group('MemberLaneBuilder', () {
    test('按成员分开累积', () {
      final MemberLaneBuilder b = MemberLaneBuilder();
      _act(b, 'a', const TeammateToolCall('rg'));
      _act(b, 'b', const TeammateToolCall('read_file'));
      _act(b, 'a', const TeammateToolResult('rg'));

      final Map<String, MemberLane> lanes = b.build(<String, bool>{});
      expect(lanes.keys.toSet(), <String>{'a', 'b'});
      expect(lanes['a']!.lines, hasLength(2));
      expect(lanes['b']!.lines, hasLength(1));
    });

    // 正文是逐字来的；若每条单独成行，一条长回答就刷掉整个泳道。
    test('连续正文合并成一行', () {
      final MemberLaneBuilder b = MemberLaneBuilder();
      _act(b, 'a', const TeammateText('查'));
      _act(b, 'a', const TeammateText('看'));
      _act(b, 'a', const TeammateText('中'));

      expect(b.build(<String, bool>{})['a']!.lines.single.text, '查看中');
    });

    test('工具行不与正文合并', () {
      final MemberLaneBuilder b = MemberLaneBuilder();
      _act(b, 'a', const TeammateText('前置'));
      _act(b, 'a', const TeammateToolCall('rg'));
      _act(b, 'a', const TeammateText('后置'));

      final List<TeamActivityLine> lines = b.build(<String, bool>{})['a']!.lines;
      expect(lines, hasLength(3));
      expect(lines[1].text, '→ rg');
    });

    test('工具后紧跟的正文另起一行（不并进工具行）', () {
      final MemberLaneBuilder b = MemberLaneBuilder();
      _act(b, 'a', const TeammateToolResult('rg'));
      _act(b, 'a', const TeammateText('找到了'));

      expect(b.build(<String, bool>{})['a']!.lines, hasLength(2));
    });

    test('思考行不与正文合并', () {
      final MemberLaneBuilder b = MemberLaneBuilder();
      _act(b, 'a', const TeammateReasoning('想'));
      _act(b, 'a', const TeammateText('答'));

      expect(b.build(<String, bool>{})['a']!.lines, hasLength(2));
    });

    test('超过上限时丢最旧的，保留最新', () {
      final MemberLaneBuilder b = MemberLaneBuilder();
      for (int i = 0; i < kTeamLaneMaxLines + 4; i++) {
        _act(b, 'a', TeammateToolCall('tool$i'));
      }

      final List<TeamActivityLine> lines = b.build(<String, bool>{})['a']!.lines;
      expect(lines, hasLength(kTeamLaneMaxLines));
      expect(lines.first.text, '→ tool4');
      expect(lines.last.text, '→ tool${kTeamLaneMaxLines + 3}');
    });

    test('失败标记透传', () {
      final MemberLaneBuilder b = MemberLaneBuilder();
      _act(b, 'a', const TeammateToolResult('rg', failed: true));

      expect(b.build(<String, bool>{})['a']!.lines.single.failed, isTrue);
    });

    test('build 带上活跃标记', () {
      final MemberLaneBuilder b = MemberLaneBuilder();
      _act(b, 'a', const TeammateToolCall('rg'));

      final Map<String, MemberLane> lanes =
          b.build(<String, bool>{'a': true, 'b': false});
      // 泳道只为**收到过事件的成员**建立；active 标记只作用在已建的泳道上。
      expect(lanes['a']!.active, isTrue);
      expect(lanes.containsKey('b'), isFalse);
    });

    test('有泳道但当前已终态：active 为 false', () {
      final MemberLaneBuilder b = MemberLaneBuilder();
      _act(b, 'a', const TeammateToolCall('rg'));

      expect(b.build(<String, bool>{})['a']!.active, isFalse);
    });

    test('remove 丢掉该成员泳道，clear 清空', () {
      final MemberLaneBuilder b = MemberLaneBuilder();
      _act(b, 'a', const TeammateToolCall('rg'));
      b.remove('a');
      expect(b.build(<String, bool>{}), isEmpty);

      _act(b, 'c', const TeammateToolCall('x'));
      b.clear();
      expect(b.build(<String, bool>{}), isEmpty);
    });

    test('非活动事件被忽略', () {
      final MemberLaneBuilder b = MemberLaneBuilder();
      b.add(TeamTaskCreated(
        TeamTask(
          id: 't1',
          description: '干活',
          status: TeamTaskStatus.pending,
          dependsOn: const <String>[],
          version: 1,
          createdAt: DateTime.utc(2026),
        ),
      ));
      expect(b.build(<String, bool>{}), isEmpty);
    });
  });

  group('TeamSubscription 折叠', () {
    // 活动是高频事件：整份重建成员表纯属浪费，故走泳道就地更新。
    test('活动事件只动泳道', () async {
      final _FakeTeam team = _FakeTeam();
      TeamSnapshot? seen;
      final TeamSubscription sub = TeamSubscription(
        team: team,
        onChanged: (TeamSnapshot s) => seen = s,
      );
      addTearDown(sub.dispose);

      // 广播流异步投递，emit 后要放一个事件循环才收得到。
      team.emit(const TeammateActed('a', TeammateToolCall('rg')));
      team.emit(const TeammateActed('a', TeammateToolResult('rg')));
      await pumpEventQueue();

      expect(sub.snapshot.lanes['a']!.lines, hasLength(2));
      expect(seen, isNotNull, reason: '每次活动都应通知重绘');
      expect(team.memberReads, 1,
          reason: '只有构造时那次读取；活动路径不该再读成员表');
    });

    test('成本来源注入时带上', () {
      final _FakeTeam team = _FakeTeam();
      final TeamSubscription sub = TeamSubscription(
        team: team,
        onChanged: (TeamSnapshot _) {},
        costSource: const _FixedCost(1.25),
      );
      addTearDown(sub.dispose);

      expect(sub.snapshot.totalCost, 1.25);
    });
  });
}

/// 固定成本的来源。
class _FixedCost implements TeamCostSource {
  const _FixedCost(this.totalCost);
  @override
  final double totalCost;
}

/// 假团队：只提供订阅与成员表读取计数，用来断言「哪条路径重读了成员表」。
///
/// 刻意不实现全部接口——`implements AgentTeam` 在这里太啰嗦，而测试只需要
/// `changes` / `members` / `tasks`。
class _FakeTeam implements AgentTeam {
  _FakeTeam([List<Teammate> seed = const <Teammate>[]]) : _members = seed;

  final StreamController<AgentTeamEvent> _changes =
      StreamController<AgentTeamEvent>.broadcast();
  final List<Teammate> _members;

  /// 读 `members` 的次数；活动路径应保持 0。
  int memberReads = 0;

  void emit(AgentTeamEvent event) => _changes.add(event);

  @override
  Stream<AgentTeamEvent> get changes => _changes.stream;

  @override
  List<Teammate> get members {
    memberReads++;
    return List<Teammate>.unmodifiable(_members);
  }

  @override
  List<TeamTask> get tasks => const <TeamTask>[];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 不在本测试覆盖范围');
}

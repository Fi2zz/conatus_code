/// 团队渲染件测试（nocterm 测试框架）：状态栏 / 成员卡片 / 任务行 / 团队视图。
library;

import 'package:conatus_code/tui.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:test/test.dart';

Teammate _mate(String id, TeammateStatus status) => Teammate(
      id: id,
      name: id,
      role: TeamRole.member,
      status: status,
      tools: const <String>[],
      createdAt: DateTime.utc(2026, 9, 17),
    );

TeamTask _task(
  String id,
  TeamTaskStatus status, {
  List<String> dependsOn = const <String>[],
  String? assigneeId,
}) =>
    TeamTask(
      id: id,
      description: '审查$id',
      status: status,
      dependsOn: dependsOn,
      version: 1,
      createdAt: DateTime.utc(2026, 9, 17),
      assigneeId: assigneeId,
    );

Future<TerminalState> _render(Component component) async {
  final NoctermTester tester = await NoctermTester.create();
  try {
    await tester.pumpComponent(component);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return tester.terminalState;
  } finally {
    tester.dispose();
  }
}

void main() {
  test('TeamStatusBar：空团队不渲染', () async {
    final TerminalState state = await _render(
      const TeamStatusBar(snapshot: TeamSnapshot()),
    );
    expect(state, isNot(containsText('团队:')));
  });

  test('TeamStatusBar：有团队显示概况，成本按开关显示', () async {
    final TeamSnapshot snapshot = TeamSnapshot(
      members: <Teammate>[
        _mate('a', TeammateStatus.working),
        _mate('b', TeammateStatus.done),
      ],
      tasks: <TeamTask>[
        _task('t1', TeamTaskStatus.done),
        _task('t2', TeamTaskStatus.claimed),
      ],
      totalCost: 1.2,
    );
    final TerminalState state = await _render(
      TeamStatusBar(snapshot: snapshot, showCost: true),
    );
    expect(state, containsText('团队: 1 成员'));
    expect(state, containsText('任务: 1/2 完成'));
    expect(state, containsText('成本: \$1.20'));
  });

  test('TeamStatusBar：showCost=false 时不显示成本', () async {
    final TerminalState state = await _render(
      TeamStatusBar(
        snapshot: TeamSnapshot(members: <Teammate>[
          _mate('a', TeammateStatus.working),
        ]),
      ),
    );
    expect(state, isNot(containsText('成本:')));
  });

  test('MemberCard：working 显示图标、状态与当前任务', () async {
    final TerminalState state = await _render(
      MemberCard(
        member: _mate('reviewer', TeammateStatus.working)
            .copyWith(currentTaskId: 't1'),
        tasks: <TeamTask>[_task('t1', TeamTaskStatus.claimed)],
      ),
    );
    expect(state, containsText('◐ reviewer  [执行中]'));
    expect(state, containsText('任务: 审查t1'));
  });

  test('MemberCard：waiting 显示等待依赖行', () async {
    final TerminalState state = await _render(
      MemberCard(
        member: _mate('reviewer', TeammateStatus.waiting),
        tasks: const <TeamTask>[],
      ),
    );
    expect(state, containsText('◌ reviewer  [等待]'));
    expect(state, containsText('等待依赖完成'));
  });

  test('TaskRow：pending 显示图标、负责人与依赖', () async {
    final TerminalState state = await _render(
      TaskRow(
        task: _task(
          't1',
          TeamTaskStatus.pending,
          dependsOn: <String>['dep1', 'dep2'],
          assigneeId: 'a',
        ),
        members: <Teammate>[_mate('a', TeammateStatus.idle)],
      ),
    );
    expect(state, containsText('○ 审查t1  [待领取]'));
    expect(state, containsText('负责: a'));
    expect(state, containsText('依赖: dep1, dep2'));
  });

  test('TaskRow：claimed 显示执行中', () async {
    final TerminalState state = await _render(
      TaskRow(
        task: _task('t1', TeamTaskStatus.claimed),
        members: const <Teammate>[],
      ),
    );
    expect(state, containsText('◐ 审查t1  [执行中]'));
  });

  test('TeamView：泳道 + 任务板按序渲染', () async {
    final TeamSnapshot snapshot = TeamSnapshot(
      members: <Teammate>[
        _mate('reviewer', TeammateStatus.working),
        _mate('idler', TeammateStatus.idle),
      ],
      tasks: <TeamTask>[
        _task('t1', TeamTaskStatus.done),
        _task('t2', TeamTaskStatus.pending),
      ],
    );
    final TerminalState state = await _render(TeamView(snapshot: snapshot));
    expect(state, containsText('团队泳道'));
    expect(state, containsText('任务板'));
    expect(state.getText().indexOf('reviewer'),
        lessThan(state.getText().indexOf('任务板')));
    expect(state, containsText('◐ reviewer  [执行中]'));
    expect(state, containsText('✓ 审查t1  [完成]'));
    expect(state, containsText('○ 审查t2  [待领取]'));
  });

  test('MemberLaneView：活动行在标题之下，失败标红', () async {
    final TerminalState state = await _render(MemberLaneView(
      id: 'researcher',
      member: _mate('researcher', TeammateStatus.working),
      lane: const MemberLane(
        active: true,
        lines: <TeamActivityLine>[
          TeamActivityLine('· 第 1 轮'),
          TeamActivityLine('→ rg'),
          TeamActivityLine('✗ read_file', failed: true),
        ],
      ),
    ));

    expect(state, containsText('◐ researcher  [执行中]'));
    expect(state.getText().indexOf('researcher'),
        lessThan(state.getText().indexOf('→ rg')));
    expect(state, containsText('✗ read_file'));
  });

  test('MemberLaneView：活动过多时只留末尾若干行', () async {
    final TerminalState state = await _render(MemberLaneView(
      id: 'w',
      member: _mate('w', TeammateStatus.working),
      lane: MemberLane(
        lines: <TeamActivityLine>[
          for (int i = 0; i < kTeamLaneMaxLines + 5; i++)
            TeamActivityLine('· 第 $i 轮'),
        ],
      ),
    ));

    expect(state.containsText('· 第 0 轮'), isFalse);
    expect(state, containsText('· 第 ${kTeamLaneMaxLines + 4} 轮'));
  });

  test('MemberLaneView：无活动时只渲染标题', () async {
    final TerminalState state = await _render(MemberLaneView(
      id: 'idle-one',
      member: _mate('idle-one', TeammateStatus.idle),
      lane: const MemberLane(),
    ));
    expect(state, containsText('○ idle-one  [空闲]'));
  });
}

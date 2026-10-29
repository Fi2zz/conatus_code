/// TeamSnapshot 纯单元测试：派生指标与可领取任务判定。
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
      description: '任务$id',
      status: status,
      dependsOn: dependsOn,
      version: 1,
      createdAt: DateTime.utc(2026, 9, 17),
      assigneeId: assigneeId,
    );

void main() {
  test('hasTeam：成员为空时为 false', () {
    expect(const TeamSnapshot().hasTeam, isFalse);
  });

  test('activeMembers：终态（done / failed）不计入', () {
    final TeamSnapshot snapshot = TeamSnapshot(members: <Teammate>[
      _mate('a', TeammateStatus.working),
      _mate('b', TeammateStatus.done),
      _mate('c', TeammateStatus.failed),
      _mate('d', TeammateStatus.waiting),
    ]);
    expect(snapshot.activeMembers, 2);
  });

  test('doneTasks / totalTasks 统计任务板', () {
    final TeamSnapshot snapshot = TeamSnapshot(tasks: <TeamTask>[
      _task('t1', TeamTaskStatus.done),
      _task('t2', TeamTaskStatus.claimed),
      _task('t3', TeamTaskStatus.pending),
    ]);
    expect(snapshot.doneTasks, 1);
    expect(snapshot.totalTasks, 3);
  });

  test('claimableBy：依赖全 done 且未分配给他人的 pending 任务', () {
    final TeamSnapshot snapshot = TeamSnapshot(tasks: <TeamTask>[
      _task('a', TeamTaskStatus.pending),
      _task('b', TeamTaskStatus.pending, dependsOn: <String>['a']),
      _task('c', TeamTaskStatus.claimed),
      _task('d', TeamTaskStatus.done),
      _task('e', TeamTaskStatus.pending, dependsOn: <String>['d']),
      _task('f', TeamTaskStatus.pending, assigneeId: 'other'),
      _task('g', TeamTaskStatus.pending, assigneeId: 'u'),
    ]);
    final List<String> ids =
        snapshot.claimableBy('u').map((TeamTask t) => t.id).toList();
    expect(ids, <String>['a', 'e', 'g']);
  });

  test('summarizeTeamProgress：无团队', () {
    expect(
      summarizeTeamProgress(const TeamSnapshot()),
      '现在没有正在进行的团队任务。',
    );
  });

  test('summarizeTeamProgress：按成员状态分组摘要', () {
    final TeamSnapshot snapshot = TeamSnapshot(
      members: <Teammate>[
        _mate('a', TeammateStatus.done),
        _mate('b', TeammateStatus.working),
        _mate('c', TeammateStatus.waiting),
        _mate('d', TeammateStatus.failed),
      ],
      tasks: <TeamTask>[
        _task('t1', TeamTaskStatus.done),
        _task('t2', TeamTaskStatus.claimed),
      ],
    );
    expect(
      summarizeTeamProgress(snapshot),
      '1/2 个任务完成。a完成了，b还在进行，c在等待，d失败了。',
    );
  });

  test('summarizeTeamProgress：全部空闲只报任务数', () {
    final TeamSnapshot snapshot = TeamSnapshot(
      members: <Teammate>[
        _mate('a', TeammateStatus.idle),
        _mate('b', TeammateStatus.idle),
      ],
      tasks: <TeamTask>[_task('t1', TeamTaskStatus.pending)],
    );
    expect(summarizeTeamProgress(snapshot), '0/1 个任务完成。');
  });
}

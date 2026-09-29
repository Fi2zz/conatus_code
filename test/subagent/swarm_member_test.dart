/// 子 Agent 活动 → 团队泳道的投影。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  late SwarmProjection swarm;
  late List<String> written;
  late List<bool> failures;

  setUp(() {
    swarm = SwarmProjection();
    written = <String>[];
    failures = <bool>[];
    swarm.sink.attach((String laneId, String line, bool failed) {
      written.add('$laneId|$line');
      failures.add(failed);
    });
  });

  test('泳道 id 带 swarm- 前缀，与团队成员 id 区分得开', () {
    swarm.report(const SubAgentStarted('调研'));

    expect(written.single, startsWith('${SwarmMember.kSwarmLanePrefix}1|'));
    expect(
      const SwarmMember(id: '${SwarmMember.kSwarmLanePrefix}1', label: 'x').projected,
      isTrue,
    );
    expect(
      const SwarmMember(id: 'researcher', label: 'x').projected,
      isFalse,
    );
  });

  test('一次委托走完：起手 → 工具 → 收口', () {
    swarm
      ..report(const SubAgentStarted('调研存储'))
      ..report(const SubAgentToolCall('rg'))
      ..report(const SubAgentToolDone('rg', false))
      ..report(const SubAgentToolCall('read_file'))
      ..report(const SubAgentToolDone('read_file', true))
      ..report(const SubAgentRound(2, '输出 80 字符'))
      ..report(const SubAgentFinished('success', 3, <String>['rg', 'read_file']));

    expect(written, <String>[
      'swarm-1|· 开始',
      'swarm-1|→ rg',
      'swarm-1|✓ rg',
      'swarm-1|→ read_file',
      'swarm-1|✗ read_file',
      'swarm-1|· 第 2 轮 输出 80 字符',
      'swarm-1|✓ 收口：3 轮 （rg、read_file）',
    ]);
  });

  test('失败标记透传（工具失败 / 委托失败）', () {
    swarm
      ..report(const SubAgentStarted('x'))
      ..report(const SubAgentToolDone('rg', true))
      ..report(const SubAgentFinished('failed', 1, <String>[]));

    expect(failures, <bool>[false, true, true]);
  });

  test('无在途委托时的事件被丢弃（不产生空泳道）', () {
    swarm
      ..report(const SubAgentToolCall('rg'))
      ..report(const SubAgentFinished('success', 1, <String>[]));

    expect(written, isEmpty);
    expect(swarm.current, isNull);
  });

  test('连续两次委托用不同泳道', () {
    swarm
      ..report(const SubAgentStarted('a'))
      ..report(const SubAgentFinished('success', 1, <String>[]))
      ..report(const SubAgentStarted('b'))
      ..report(const SubAgentFinished('success', 1, <String>[]));

    expect(written.first, startsWith('swarm-1|'));
    expect(written.last, startsWith('swarm-2|'));
    expect(swarm.runs, 2);
  });

  test('sink 未接上时静默丢弃，不抛异常', () {
    final SwarmProjection loose = SwarmProjection();
    expect(
      () => loose
        ..report(const SubAgentStarted('x'))
        ..report(const SubAgentFinished('success', 1, <String>[])),
      returnsNormally,
    );
  });

  test('泳道名字登记在 labels 里，供视图渲染', () {
    swarm
      ..report(const SubAgentStarted('x'))
      ..report(const SubAgentFinished('success', 1, <String>[]));

    expect(swarm.labels['swarm-1'], '子 Agent #1');
  });
}

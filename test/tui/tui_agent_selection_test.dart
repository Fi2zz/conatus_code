/// 会话级 Agent 选择：标签之间不泄漏，/new 回到配置默认 Agent。
library;

import 'package:conatus_code/providers.dart';
import 'package:conatus_code/tui.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'agent_command_fakes.dart';
import 'agent_command_support.dart';

void main() {
  test('build → plan 后新标签用默认 build，切回旧标签恢复 plan', () async {
    final CommandHarness harness = await buildCommandHarness();
    addTearDown(harness.dispose);

    expect(harness.controller.agentId, 'build');
    expect(await harness.controller.switchAgent('plan'), isTrue);
    expect(harness.controller.agentId, 'plan');
    expect(harness.controller.planModeActive, isTrue);

    await harness.controller.handleLine('/new');

    expect(harness.controller.agentId, 'build');
    expect(harness.controller.planModeActive, isFalse);

    expect(await harness.controller.activateTab(0), isTrue);
    expect(harness.controller.agentId, 'plan');
  });

  test('启动时把命令 / Agent 发现告警上屏', () async {
    final CommandHarness harness = await buildCommandHarness(
      extraFiles: <String, String>{
        '.nava/commands/bad.md': '---\nagent: 1\n---\nbad\n',
      },
    );
    addTearDown(harness.dispose);

    expect(
      harness.controller.transcript.messages.any(
        (TuiMessage message) => message.text.contains('bad.md'),
      ),
      isTrue,
    );
  });

  test('切回标签后真实请求使用该会话 Agent 的模型', () async {
    final (
      ProviderRegistry registry,
      List<http.Request> requests,
    ) = buildRecordingRegistry(<String, List<String>>{
      'alpha': <String>['a1'],
      'beta': <String>['b1'],
    });
    final CommandHarness harness = await buildCommandHarness(
      agents: <String, String>{
        'agent_a.md': '---\nmode: primary\nmodel: alpha/a1\n---\nA',
        'agent_b.md': '---\nmode: primary\nmodel: beta/b1\n---\nB',
      },
      registry: registry,
      chainEntries: <String>['alpha/a1'],
    );
    addTearDown(harness.dispose);

    expect(await harness.controller.switchAgent('agent_a'), isTrue);
    await harness.controller.handleLine('A 第一轮');
    expect(requestModel(requests.last), 'a1');

    await harness.controller.handleLine('/new');
    expect(await harness.controller.switchAgent('agent_b'), isTrue);
    await harness.controller.handleLine('B 第一轮');
    expect(requestModel(requests.last), 'b1');

    expect(await harness.controller.activateTab(0), isTrue);
    await harness.controller.handleLine('A 返回后');
    expect(requestModel(requests.last), 'a1');
  });

  test('切换 Agent 以 agent/selected 事件持久化', () async {
    final CommandHarness harness = await buildCommandHarness();
    addTearDown(harness.dispose);

    await harness.controller.switchAgent('plan');
    final session = harness.controller.session!;

    final event = session.ownEvents
        .where((event) => event.type == 'agent/selected')
        .last;
    expect((event.data as Map)['id'], 'plan');
  });
}

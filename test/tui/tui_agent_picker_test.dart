/// `/agents` 选择面板：可见性、仅子 Agent 条目与主会话切换。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/providers.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'agent_command_fakes.dart';
import 'agent_command_support.dart';

const Map<String, String> _agents = <String, String>{
  'reviewer.md': '---\ndescription: 代码审查\nmode: primary\n---\n你是审查者。',
  'secret.md': '---\nhidden: true\n---\n隐藏 Agent',
  'dual.md': '---\nmode: all\n---\n双用途 Agent',
};

void main() {
  test('visible 列表排除 hidden，仅子 Agent 条目不可选', () async {
    final CommandHarness harness = await buildCommandHarness(agents: _agents);
    addTearDown(harness.dispose);

    harness.controller.openAgentPicker();
    final AgentPicker picker = harness.controller.agentPicker;
    final List<String> ids = picker.list
        .map((AgentDefinition a) => a.id)
        .toList();

    expect(picker.open, isTrue);
    expect(ids, containsAll(<String>['build', 'plan', 'reviewer', 'dual']));
    expect(ids, containsAll(<String>['explore', 'general']));
    expect(ids, isNot(contains('secret')));
    expect(picker.selectableAt(indexOfAgent(picker.list, 'explore')), isFalse);
    expect(picker.selectableAt(indexOfAgent(picker.list, 'general')), isFalse);
    expect(picker.selectableAt(indexOfAgent(picker.list, 'reviewer')), isTrue);
  });

  test('选择 plan 切换 Agent 并进入 Plan Mode，选择 build 退出', () async {
    final CommandHarness harness = await buildCommandHarness(agents: _agents);
    addTearDown(harness.dispose);

    harness.controller.openAgentPicker();
    final AgentPicker picker = harness.controller.agentPicker;
    picker.index = indexOfAgent(picker.list, 'plan');
    await harness.controller.pickAgent();

    expect(picker.open, isFalse);
    expect(harness.controller.agentId, 'plan');
    expect(harness.controller.planModeActive, isTrue);
    final PermissionWiring wiring = harness.app.get<PermissionWiring>(
      'permissionWiring',
    )!;
    expect(wiring.slot.current.agentId, 'plan');
    expect(
      wiring.rules.any(
        (PermissionRule rule) =>
            rule.action == 'edit' && rule.effect == PermissionEffect.deny,
      ),
      isTrue,
    );

    harness.controller.openAgentPicker();
    picker.index = indexOfAgent(picker.list, 'build');
    await harness.controller.pickAgent();

    expect(harness.controller.agentId, 'build');
    expect(harness.controller.planModeActive, isFalse);
    expect(wiring.slot.current.agentId, 'build');
    expect(
      wiring.rules.any(
        (PermissionRule rule) =>
            rule.action == 'edit' &&
            rule.effect == PermissionEffect.deny &&
            rule.source == 'builtin',
      ),
      isFalse,
    );
  });

  test('选择仅子 Agent 条目只提示，不切换主 Agent', () async {
    final CommandHarness harness = await buildCommandHarness(agents: _agents);
    addTearDown(harness.dispose);

    harness.controller.openAgentPicker();
    final AgentPicker picker = harness.controller.agentPicker;
    picker.index = indexOfAgent(picker.list, 'explore');
    await harness.controller.pickAgent();

    expect(harness.controller.agentId, 'build');
    expect(
      harness.controller.transcript.messages.last.text,
      contains('只能作为子 Agent'),
    );
  });

  test('光标移动跳过仅子 Agent 条目', () async {
    final CommandHarness harness = await buildCommandHarness(agents: _agents);
    addTearDown(harness.dispose);

    harness.controller.openAgentPicker();
    final AgentPicker picker = harness.controller.agentPicker;
    picker.index = indexOfAgent(picker.list, 'plan');
    harness.controller.moveAgentPicker(1);

    expect(picker.selectedAgent, isNotNull);
    expect(picker.selectedAgent!.mode, isNot(AgentMode.subagent));
  });

  test('从带 model 的 Agent 切回 build 恢复非 Agent 基线模型', () async {
    final (
      ProviderRegistry registry,
      List<http.Request> requests,
    ) = buildRecordingRegistry(<String, List<String>>{
      'alpha': <String>['a1'],
      'beta': <String>['b1'],
    });
    final CommandHarness harness = await buildCommandHarness(
      agents: <String, String>{
        'reviewer.md': '---\nmodel: beta/b1\n---\n你是审查者。',
      },
      registry: registry,
      chainEntries: <String>['alpha/a1'],
    );
    addTearDown(harness.dispose);
    expect(harness.controller.modelLabel, 'a1');

    expect(await harness.controller.switchAgent('reviewer'), isTrue);
    expect(harness.controller.modelLabel, 'b1');

    expect(await harness.controller.switchAgent('build'), isTrue);
    expect(harness.controller.modelLabel, 'a1');
    await harness.controller.handleLine('普通提问');
    expect(requestModel(requests.last), 'a1');
  });

  test('[agent] default_agent 作为启动 Agent', () async {
    final CommandHarness harness = await buildCommandHarness(
      agents: _agents,
      defaultAgent: 'reviewer',
    );
    addTearDown(harness.dispose);

    expect(harness.controller.agentId, 'reviewer');
  });

  test('未知 / 仅子 Agent 的启动配置回退到默认主 Agent', () async {
    final CommandHarness harness = await buildCommandHarness(
      agents: _agents,
      defaultAgent: 'explore',
    );
    addTearDown(harness.dispose);

    expect(harness.controller.agentId, 'build');
  });
}

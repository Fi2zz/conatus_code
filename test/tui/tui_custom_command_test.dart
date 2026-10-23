/// 自定义命令接入 TUI：分发、内置优先、shell 错误与 Agent/Model 覆盖。
library;


import 'package:conatus_code/providers.dart';
import 'package:conatus_code/tui.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'agent_command_fakes.dart';
import 'agent_command_support.dart';

void main() {
  test('自定义命令展开参数并提交', () async {
    final CommandHarness harness = await buildCommandHarness(
      commands: <String, String>{
        'draft.md': '---\ndescription: 起草\n---\n请处理：\$ARGUMENTS',
      },
    );
    addTearDown(harness.dispose);

    await harness.controller.handleLine('/draft src/a.dart');

    expect(harness.provider.turns, hasLength(1));
    expect(harness.provider.turns.single.prompt, contains('请处理：src/a.dart'));
    expect(
      harness.controller.transcript.messages.any(
        (TuiMessage m) => m.text.contains('src/a.dart'),
      ),
      isTrue,
    );
  });

  test('内置命令优先：/exit 压过 .nava/commands/exit.md', () async {
    final CommandHarness harness = await buildCommandHarness(
      commands: <String, String>{'exit.md': '---\n---\n不该执行的自定义命令'},
    );
    addTearDown(harness.dispose);

    await harness.controller.handleLine('/exit');

    expect(harness.exited.single, isTrue);
    expect(harness.provider.turns, isEmpty);
  });

  test('内置 /review 不会被同名命令覆盖', () async {
    final CommandHarness harness = await buildCommandHarness(
      commands: <String, String>{'review.md': '---\n---\n自定义审查'},
    );
    addTearDown(harness.dispose);

    await harness.controller.handleLine('/review');

    expect(harness.provider.turns.single.prompt, contains('只审不改'));
    expect(harness.provider.turns.single.prompt, isNot(contains('自定义审查')));
  });

  test('shell 块失败只上屏提示，不提交 prompt', () async {
    final CommandHarness harness = await buildCommandHarness(
      commands: <String, String>{'broken.md': '---\n---\n先执行 !`exit 7` 再继续'},
      withShell: true,
    );
    addTearDown(harness.dispose);

    await harness.controller.handleLine('/broken');

    expect(harness.provider.turns, isEmpty);
    final String last = harness.controller.transcript.messages.last.text;
    expect(last, contains('展开失败'));
    expect(last, contains('exit 7'));
  });

  test('agent: plan 在本轮切换 Agent 与 Plan Mode，结束后恢复', () async {
    final CommandHarness harness = await buildCommandHarness(
      commands: <String, String>{
        'plan-now.md': '---\nagent: plan\n---\n给出计划：\$ARGUMENTS',
      },
    );
    addTearDown(harness.dispose);

    await harness.controller.handleLine('/plan-now 登录流程');

    final CapturedTurn turn = harness.provider.turns.single;
    expect(turn.prompt, contains('给出计划：登录流程'));
    expect(turn.agentId, 'plan');
    expect(turn.planModeActive, isTrue);
    expect(harness.controller.agentId, 'build');
    expect(harness.controller.planModeActive, isFalse);
  });

  test('model 覆盖本轮生效，轮末恢复原模型', () async {
    final (
      ProviderRegistry registry,
      List<http.Request> requests,
    ) = buildRecordingRegistry(<String, List<String>>{
      'alpha': <String>['a1'],
      'beta': <String>['b1'],
    });
    final CommandHarness harness = await buildCommandHarness(
      commands: <String, String>{
        'draft.md': '---\nmodel: beta/b1\n---\n请起草：\$ARGUMENTS',
      },
      registry: registry,
      chainEntries: <String>['alpha/a1'],
    );
    addTearDown(harness.dispose);
    expect(harness.controller.modelLabel, 'a1');

    await harness.controller.handleLine('/draft 说明');

    expect(requests, isNotEmpty);
    expect(requestModel(requests.last), 'b1');
    expect(harness.controller.modelLabel, 'a1');

    await harness.controller.handleLine('普通提问');
    expect(requestModel(requests.last), 'a1');
  });

  test('subagent: true 前台执行 spawn_agent 并写入结果', () async {
    final CommandHarness harness = await buildCommandHarness(
      commands: <String, String>{
        'research.md':
            '---\nagent: explore\nsubagent: true\n---\n调研：\$ARGUMENTS',
      },
      withSpawn: true,
    );
    addTearDown(harness.dispose);

    await harness.controller.handleLine('/research src/core');

    expect(harness.spawn.calls, hasLength(1));
    expect(harness.spawn.calls.single['task'], contains('调研：src/core'));
    expect(harness.spawn.calls.single['agent'], 'explore');
    expect(harness.provider.turns, isEmpty);
    expect(
      harness.controller.transcript.messages.last.text,
      contains('fake-spawn'),
    );
  });

  test('启动 Agent 自带 model 时首轮即使用该模型', () async {
    final (
      ProviderRegistry registry,
      List<http.Request> requests,
    ) = buildRecordingRegistry(<String, List<String>>{
      'alpha': <String>['a1'],
      'beta': <String>['b1'],
    });
    final CommandHarness harness = await buildCommandHarness(
      agents: <String, String>{
        'reviewer.md': '---\nmode: primary\nmodel: beta/b1\n---\n你是审查者。',
      },
      defaultAgent: 'reviewer',
      registry: registry,
      chainEntries: <String>['alpha/a1'],
    );
    addTearDown(harness.dispose);

    expect(harness.controller.agentId, 'reviewer');
    expect(harness.controller.modelLabel, 'b1');
    await harness.controller.handleLine('看一下');
    expect(requestModel(requests.last), 'b1');
  });

  test('命令菜单包含自定义命令，内置仍排在最前', () async {
    final CommandHarness harness = await buildCommandHarness(
      commands: <String, String>{
        'draft.md':
            '---\ndescription: 起草\nagent: plan\nmodel: beta/b1\n---\n正文',
      },
    );
    addTearDown(harness.dispose);

    final List<TuiCommand> commands = harness.controller.commands;
    expect(commands.first.name, tuiCommands.first.name);
    expect(
      commands.take(tuiCommands.length).map((TuiCommand c) => c.name),
      tuiCommands.map((TuiCommand c) => c.name),
    );
    final TuiCommand draft = commands.firstWhere(
      (TuiCommand c) => c.name == 'draft',
    );
    expect(draft.description, contains('agent: plan'));
    expect(draft.description, contains('model: beta/b1'));
  });
}

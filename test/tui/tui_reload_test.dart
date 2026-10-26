/// `/reload`：重新发现命令 / Agent 定义。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

import '../agents/agent_test_support.dart';
import '../commands/command_test_support.dart';
import 'agent_command_support.dart';

void main() {
  test('reloadDefinitions 发现新命令与新 Agent', () async {
    final CommandHarness harness = await buildCommandHarness();
    addTearDown(harness.dispose);
    writeCommand(
      Directory('${harness.work.path}/.nava/commands'),
      'late.md',
      'late template',
    );
    writeAgent(
      Directory('${harness.work.path}/.nava/agents'),
      'late.md',
      body: 'late body',
    );

    await harness.controller.reloadDefinitions();

    final CommandRegistry commands =
        harness.app.require<CommandRegistry>('commandRegistry');
    final AgentRegistry agents =
        harness.app.require<AgentRegistry>('agentRegistry');
    expect(commands.byName('late')!.template, 'late template');
    expect(agents.byId('late')!.system, 'late body');
  });
}

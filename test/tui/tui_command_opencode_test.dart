/// `.opencode` 只读：自定义命令执行与 `/agents` 选择都不写用户目录。
library;

import 'dart:io';

import 'package:test/test.dart';

import 'agent_command_fakes.dart';
import 'agent_command_support.dart';

void main() {
  test('.opencode 目录在执行命令与 /agents 后内容不变', () async {
    final CommandHarness harness = await buildCommandHarness(
      commands: <String, String>{
        'draft.md': '---\nagent: plan\n---\n正文 \$ARGUMENTS',
      },
      extraFiles: <String, String>{
        '.opencode/commands/opencode-only.md': '---\n---\n只读命令',
        '.opencode/agents/reviewer.md': '---\n---\n只读 Agent',
      },
    );
    addTearDown(harness.dispose);
    final Directory opencode = Directory('${harness.work.path}/.opencode');
    final List<String> before = snapshotTree(opencode);

    await harness.controller.handleLine('/draft x');
    harness.controller.openAgentPicker();
    harness.controller.closeAgentPicker();

    expect(snapshotTree(opencode), before);
  });
}

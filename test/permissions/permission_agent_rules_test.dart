/// Agent 自带权限规则只收紧：allow 被丢弃，deny 追加在最后。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  test('Agent allow 不会放宽 config deny', () {
    final Directory dir = Directory.systemTemp.createTempSync('perm-agent-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final PermissionWiring wiring = PermissionWiring(
      store: PermissionStore('${dir.path}/permissions.json'),
      configRules: <PermissionRule>[
        const PermissionRule(
          action: 'edit',
          resource: '*',
          effect: PermissionEffect.deny,
          source: 'config',
        ),
      ],
    );

    wiring.setAgentRules(<PermissionRule>[
      const PermissionRule(
        action: 'edit',
        resource: '*',
        effect: PermissionEffect.allow,
        source: 'agent',
      ),
      const PermissionRule(
        action: 'bash',
        resource: 'git push *',
        effect: PermissionEffect.deny,
        source: 'agent',
      ),
    ]);

    expect(
      wiring.rules.where(
        (PermissionRule rule) =>
            rule.source == 'agent' && rule.effect == PermissionEffect.allow,
      ),
      isEmpty,
    );
    expect(wiring.rules.last.action, 'bash');
    expect(wiring.rules.last.effect, PermissionEffect.deny);
  });

  test('applyMode 写入 Agent 标识到作用域', () {
    final Directory dir = Directory.systemTemp.createTempSync('perm-agent-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final PermissionWiring wiring = PermissionWiring(
      store: PermissionStore('${dir.path}/permissions.json'),
    );

    wiring.applyMode(askThreshold: ToolRisk.high, agentId: 'plan');

    expect(wiring.slot.current.agentId, 'plan');
  });
}

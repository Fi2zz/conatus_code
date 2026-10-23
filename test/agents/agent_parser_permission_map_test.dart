/// Agent 解析的 OpenCode 兼容：`permission` 映射（扁平与嵌套）与提示。
library;

import 'package:conatus_agent/conatus_agent.dart'
    show PermissionEffect, PermissionRule;
import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

AgentDefinition parse(String text) =>
    parseAgentDocument(text, id: 'reviewer', sourcePath: '/tmp/reviewer.md')!;

void main() {
  test('permission 扁平映射转成通配规则并映射动作', () {
    final AgentDefinition def = parse('''
---
permission:
  edit: deny
  bash: ask
---
body
''');

    expect(def.permissions, hasLength(2));
    expect(def.permissions[0].action, 'edit');
    expect(def.permissions[0].resource, '*');
    expect(def.permissions[0].effect, PermissionEffect.deny);
    expect(def.permissions[1].action, 'shell');
    expect(def.permissions[1].effect, PermissionEffect.ask);
  });

  test('permission 嵌套映射按资源 pattern 生成规则', () {
    final AgentDefinition def = parse('''
---
permission:
  bash:
    "*": ask
    "git diff": allow
  edit: deny
---
body
''');

    expect(def.permissions, hasLength(3));
    final PermissionRule wildcard = def.permissions.firstWhere(
      (PermissionRule rule) => rule.action == 'shell' && rule.resource == '*',
    );
    final PermissionRule command = def.permissions.firstWhere(
      (PermissionRule rule) =>
          rule.action == 'shell' && rule.resource == 'git diff',
    );
    expect(wildcard.effect, PermissionEffect.ask);
    expect(command.effect, PermissionEffect.allow);
    expect(def.permissions.last.action, 'edit');
    expect(def.permissions.last.effect, PermissionEffect.deny);
  });

  test('permissions 数组在前、permission 映射在后（映射优先）', () {
    final AgentDefinition def = parse('''
---
permissions:
  - action: edit
    resource: "*"
    effect: allow
permission:
  edit: deny
---
body
''');

    expect(def.permissions, hasLength(2));
    expect(def.permissions.last.action, 'edit');
    expect(def.permissions.last.effect, PermissionEffect.deny);
  });

  test('task 动作映射为 subagent', () {
    final AgentDefinition def = parse('''
---
permission:
  task: ask
---
body
''');

    expect(def.permissions.single.action, 'subagent');
    expect(def.permissions.single.effect, PermissionEffect.ask);
  });

  test('无对应工具的 OpenCode 动作告警并忽略规则', () {
    final AgentParseResult result = parseAgentDocumentDetailed(
      '''
---
permission:
  todowrite: deny
  list: ask
  lsp: allow
---
body
''',
      id: 'unsupported',
      sourcePath: '/tmp/unsupported.md',
    );

    expect(result.definition!.permissions, isEmpty);
    expect(result.warnings, hasLength(3));
    expect(result.warnings.first, contains('todowrite'));
  });

  test('未知权限动作保留原值并产生警告', () {
    final AgentParseResult result = parseAgentDocumentDetailed(
      '''
---
permission:
  edti: deny
---
body
''',
      id: 'typo',
      sourcePath: '/tmp/typo.md',
    );

    expect(result.definition, isNotNull);
    expect(result.definition!.permissions.single.action, 'edti');
    expect(result.warnings.single, contains('edti'));
  });

  test('MCP 风格动作不产生未知动作警告', () {
    final AgentParseResult result = parseAgentDocumentDetailed(
      '''
---
permission:
  server__tool: allow
---
body
''',
      id: 'mcp',
      sourcePath: '/tmp/mcp.md',
    );

    expect(result.definition!.permissions.single.action, 'server_tool');
    expect(result.warnings, isEmpty);
  });

  test('非法权限条目返回 null', () {
    const List<String> invalid = <String>[
      '---\npermissions: nope\n---\nbody',
      '---\npermissions:\n  - action: edit\n    resource: "*"\n---\nbody',
      '---\npermissions:\n  - action: edit\n    resource: "*"\n    effect: maybe\n---\nbody',
      '---\npermissions:\n  - action: 3\n    resource: "*"\n    effect: deny\n---\nbody',
      '---\npermission: edit\n---\nbody',
      '---\npermission:\n  edit: sometimes\n---\nbody',
      '---\npermission:\n  bash: 3\n---\nbody',
      '---\npermission:\n  bash:\n    "*": 3\n---\nbody',
    ];
    for (final String text in invalid) {
      expect(
        parseAgentDocument(text, id: 'bad', sourcePath: '/tmp/bad.md'),
        isNull,
        reason: text,
      );
    }
  });
}

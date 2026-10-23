/// Agent 解析的 OpenCode 兼容：`permission` 映射、`tools` 表与提示。
library;

import 'package:conatus_agent/conatus_agent.dart' show PermissionEffect;
import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

AgentDefinition parse(String text) =>
    parseAgentDocument(text, id: 'reviewer', sourcePath: '/tmp/reviewer.md')!;

void main() {
  test('permission 映射转成通配权限规则并映射动作', () {
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

  test('tools 表只保留 true 项并映射为 nava 工具名', () {
    final AgentDefinition def = parse('''
---
tools:
  write: false
  read: true
  bash: true
---
body
''');

    expect(def.tools, contains('read_file'));
    expect(def.tools, contains('run_command'));
    expect(def.tools, isNot(contains('write_file')));
  });

  test('tools 数组仍可用，并映射 OpenCode 工具名', () {
    final AgentDefinition def = parse('''
---
tools:
  - read
  - grep
  - custom_tool
---
body
''');

    expect(def.tools, <String>['read_file', 'rg', 'custom_tool']);
  });

  test('tools: [] 表示禁止所有工具', () {
    final AgentDefinition def = parse('''
---
tools: []
---
body
''');

    expect(def.tools, isEmpty);
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

  test('BOM、前导空行与 CRLF 不影响 frontmatter', () {
    final AgentDefinition def = parse(
      '\uFEFF\n\n---\r\nmode: subagent\r\ndescription: crlf\r\n---\r\nbody',
    );

    expect(def.mode, AgentMode.subagent);
    expect(def.description, 'crlf');
    expect(def.system, 'body');
  });

  test('形似围栏的首行产生警告并按纯正文解析', () {
    final AgentParseResult result = parseAgentDocumentDetailed(
      '----\nmode: subagent\n---\nbody',
      id: 'typo',
      sourcePath: '/tmp/typo.md',
    );

    expect(result.definition!.mode, AgentMode.primary);
    expect(result.definition!.system, startsWith('----'));
    expect(result.warnings.single, contains('frontmatter'));
  });

  test('非法权限条目返回 null', () {
    const List<String> invalid = <String>[
      '---\npermissions: nope\n---\nbody',
      '---\npermissions:\n  - action: edit\n    resource: "*"\n---\nbody',
      '---\npermissions:\n  - action: edit\n    resource: "*"\n    effect: maybe\n---\nbody',
      '---\npermissions:\n  - action: 3\n    resource: "*"\n    effect: deny\n---\nbody',
      '---\npermission: edit\n---\nbody',
      '---\npermission:\n  edit: sometimes\n---\nbody',
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

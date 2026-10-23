/// Agent 文档解析：frontmatter 字段校验、权限转换与正文系统提示。
library;

import 'package:conatus_agent/conatus_agent.dart' show PermissionEffect;
import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  test('parses agent permissions and mode', () {
    final AgentDefinition def = parseAgentDocument(
      '''
---
description: reviewer
mode: subagent
model: ark/doubao-seed-2-0-lite
steps: 6
permissions:
  - action: edit
    resource: "*"
    effect: deny
---
Review only.
''',
      id: 'reviewer',
      sourcePath: '/tmp/reviewer.md',
    )!;

    expect(def.id, 'reviewer');
    expect(def.description, 'reviewer');
    expect(def.mode, AgentMode.subagent);
    expect(def.model, 'ark/doubao-seed-2-0-lite');
    expect(def.steps, 6);
    expect(def.permissions.single.action, 'edit');
    expect(def.permissions.single.resource, '*');
    expect(def.permissions.single.effect, PermissionEffect.deny);
    expect(def.system, 'Review only.');
    expect(def.sourcePath, '/tmp/reviewer.md');
  });

  test('缺省字段使用 primary、空权限与未限制工具', () {
    final AgentDefinition def = parseAgentDocument(
      '''
---
---
body
''',
      id: 'plain',
      sourcePath: '/tmp/plain.md',
    )!;

    expect(def.description, '');
    expect(def.mode, AgentMode.primary);
    expect(def.steps, isNull);
    expect(def.tools, isNull);
    expect(def.permissions, isEmpty);
    expect(def.hidden, isFalse);
    expect(def.color, isNull);
    expect(def.model, isNull);
  });

  test('tools、hidden 与 color 原样解析', () {
    final AgentDefinition def = parseAgentDocument(
      '''
---
description: read only
mode: all
tools:
  - read_file
  - rg
hidden: true
color: "#ff6b6b"
---
body
''',
      id: 'reader',
      sourcePath: '/tmp/reader.md',
    )!;

    expect(def.mode, AgentMode.all);
    expect(def.tools, <String>['read_file', 'rg']);
    expect(def.hidden, isTrue);
    expect(def.color, '#ff6b6b');
  });

  test('路径类权限动作规范化资源', () {
    final AgentDefinition def = parseAgentDocument(
      '''
---
permissions:
  - action: edit_file
    resource: "./src/../lib/*"
    effect: ask
---
body
''',
      id: 'paths',
      sourcePath: '/tmp/paths.md',
    )!;

    expect(def.permissions.single.action, 'edit');
    expect(def.permissions.single.effect, PermissionEffect.ask);
    expect(def.permissions.single.resource, isNot(contains('..')));
  });

  test('无 frontmatter 时整篇正文作为系统提示', () {
    final AgentDefinition def = parseAgentDocument(
      'just a system prompt',
      id: 'plain',
      sourcePath: '/tmp/plain.md',
    )!;

    expect(def.system, 'just a system prompt');
    expect(def.mode, AgentMode.primary);
    expect(def.description, '');
  });

  test('允许空正文', () {
    final AgentDefinition def = parseAgentDocument(
      '''
---
description: empty
---
''',
      id: 'empty',
      sourcePath: '/tmp/empty.md',
    )!;

    expect(def.system, '');
    expect(def.description, 'empty');
  });

  test('未知字段忽略', () {
    final AgentDefinition def = parseAgentDocument(
      '''
---
description: x
unknown: y
---
body
''',
      id: 'x',
      sourcePath: '/tmp/x.md',
    )!;

    expect(def.description, 'x');
  });

  test('名称为空时返回 null', () {
    expect(
      parseAgentDocument('body', id: '  ', sourcePath: '/tmp/x.md'),
      isNull,
    );
  });

  test('字段类型错误时返回 null', () {
    const List<String> invalid = <String>[
      '---\nmode: helper\n---\nbody',
      '---\nmode: 3\n---\nbody',
      '---\nsteps: many\n---\nbody',
      '---\nsteps: 0\n---\nbody',
      '---\ntools: read_file\n---\nbody',
      '---\ntools:\n  - 3\n---\nbody',
      '---\nhidden: yes-please\n---\nbody',
      '---\ncolor: 3\n---\nbody',
      '---\ndescription: [unclosed\n---\nbody',
      '---\ndescription: missing closer\nbody',
    ];
    for (final String text in invalid) {
      expect(
        parseAgentDocument(text, id: 'bad', sourcePath: '/tmp/bad.md'),
        isNull,
        reason: text,
      );
    }
  });

  test('非法权限条目返回 null', () {
    const List<String> invalid = <String>[
      '---\npermissions: nope\n---\nbody',
      '---\npermissions:\n  - action: edit\n    resource: "*"\n---\nbody',
      '---\npermissions:\n  - action: edit\n    resource: "*"\n    effect: maybe\n---\nbody',
      '---\npermissions:\n  - action: 3\n    resource: "*"\n    effect: deny\n---\nbody',
    ];
    for (final String text in invalid) {
      expect(
        parseAgentDocument(text, id: 'bad', sourcePath: '/tmp/bad.md'),
        isNull,
        reason: text,
      );
    }
  });

  test('详细解析给出可诊断原因', () {
    final AgentParseResult result = parseAgentDocumentDetailed(
      '''
---
mode: helper
---
body
''',
      id: 'bad',
      sourcePath: '/tmp/bad.md',
    );

    expect(result.definition, isNull);
    expect(result.error, contains('mode'));
  });
}

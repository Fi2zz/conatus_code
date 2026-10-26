/// Agent 解析的 OpenCode 兼容：`tools` 表语义与文档边界。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

AgentDefinition parse(String text) =>
    parseAgentDocument(text, id: 'reviewer', sourcePath: '/tmp/reviewer.md')!;

void main() {
  test('tools 表的 false 项进入 disabledTools，tools 保持 null', () {
    final AgentDefinition def = parse('''
---
tools:
  write: false
  edit: false
  bash: false
---
body
''');

    expect(def.tools, isNull);
    expect(
      def.disabledTools,
      containsAll(<String>['write_file', 'edit_file', 'run_command']),
    );
  });

  test('tools 表的 true 项不产生白名单或禁用项', () {
    final AgentDefinition def = parse('''
---
tools:
  write: false
  read: true
  grep: true
---
body
''');

    expect(def.tools, isNull);
    expect(def.disabledTools, <String>['write_file']);
  });

  test('tools 数组仍是显式白名单并映射 OpenCode 工具名', () {
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
    expect(def.disabledTools, isEmpty);
  });

  test('question 工具名映射为 ask_user', () {
    final AgentDefinition def = parse('''
---
tools:
  - question
  - todowrite
---
body
''');

    expect(def.tools, <String>['ask_user', 'update_plan']);
  });

  test('tools: [] 表示禁止所有工具', () {
    final AgentDefinition def = parse('''
---
tools: []
---
body
''');

    expect(def.tools, isEmpty);
    expect(def.disabledTools, isEmpty);
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
}

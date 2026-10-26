/// OpenCode 导入计划：TOML 合并、去重、片段与可解析性。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';
import 'package:toml/toml.dart';

OpenCodeImport _import() => const OpenCodeImport(
  model: 'deepseek/deepseek-chat',
  defaultAgent: 'plan',
  mcpServers: <McpServerSpec>[
    McpServerSpec(
      name: 'fs',
      type: McpServerType.stdio,
      command: 'npx',
      args: <String>['-y', 'server-filesystem'],
      env: <String, String>{'TOKEN': r'${TOKEN}'},
    ),
    McpServerSpec(
      name: 'remote',
      type: McpServerType.http,
      url: 'https://mcp.example.com/mcp',
      headers: <String, String>{'Authorization': r'Bearer ${KEY}'},
    ),
  ],
  permissions: <ImportedPermission>[
    ImportedPermission(
      action: 'shell',
      resource: 'git push *',
      effect: 'ask',
    ),
  ],
  instructions: <String>['CONTRIBUTING.md'],
  skillDirs: <String>['/tmp/team-skills'],
);

void _expectParseable(String toml) {
  expect(() => TomlDocument.parse(toml).toMap(), returnsNormally);
}

void main() {
  test('空配置生成完整片段且可解析', () {
    final OpenCodeImportPlan plan = planOpenCodeImport(
      toml: '',
      import: _import(),
    );

    _expectParseable(plan.updatedToml);
    expect(plan.updatedToml, contains('[llm]'));
    expect(plan.updatedToml, contains('default_model = "deepseek/deepseek-chat"'));
    expect(plan.updatedToml, contains('[agent]'));
    expect(plan.updatedToml, contains('default_agent = "plan"'));
    expect(plan.updatedToml, contains('[mcp.servers.fs]'));
    expect(plan.updatedToml, contains(r'env = { TOKEN = "${TOKEN}" }'));
    expect(plan.updatedToml, contains('[[permissions]]'));
    expect(plan.updatedToml, contains('instructions = [ "CONTRIBUTING.md" ]'));
    expect(plan.updatedToml, contains('extra_skill_dirs = [ "/tmp/team-skills" ]'));
    expect(plan.snippet, contains('[mcp.servers.fs]'));
    expect(plan.added, hasLength(7));
    expect(plan.skipped, isEmpty);
  });

  test('已有同名 MCP / model / agent 时跳过，不覆盖', () {
    const String existing = '''
[llm]
default_model = "old/model"

[agent]
default_agent = "build"

[mcp.servers.fs]
command = "old"
''';

    final OpenCodeImportPlan plan = planOpenCodeImport(
      toml: existing,
      import: _import(),
    );

    _expectParseable(plan.updatedToml);
    expect(plan.updatedToml, contains('default_model = "old/model"'));
    expect(plan.updatedToml, contains('default_agent = "build"'));
    expect(plan.updatedToml, contains('command = "old"'));
    expect(plan.updatedToml, isNot(contains('default_model = "deepseek')));
    expect(plan.updatedToml, contains('[mcp.servers.remote]'));
    expect(plan.skipped, hasLength(3));
  });

  test('已有 instructions 时整体跳过并给出提示', () {
    const String existing = '''
instructions = ["AGENTS.md"]
''';

    final OpenCodeImportPlan plan = planOpenCodeImport(
      toml: existing,
      import: _import(),
    );

    expect(plan.updatedToml, contains('instructions = ["AGENTS.md"]'));
    expect(plan.updatedToml, isNot(contains('CONTRIBUTING.md')));
    expect(plan.skipped.join('\n'), contains('instructions'));
  });

  test('重复 permissions 不重复写', () {
    const String existing = '''
[[permissions]]
action = "shell"
resource = "git push *"
effect = "ask"
''';

    final OpenCodeImportPlan plan = planOpenCodeImport(
      toml: existing,
      import: _import(),
    );

    final int count = '[[permissions]]'.allMatches(plan.updatedToml).length;
    expect(count, 1);
  });

  test('非法 TOML 抛 FormatException', () {
    expect(
      () => planOpenCodeImport(toml: '[bad', import: _import()),
      throwsA(isA<FormatException>()),
    );
  });
}

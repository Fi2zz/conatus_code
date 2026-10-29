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
      action: 'bash',
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
    expect(plan.updatedToml, contains('action = "bash"'));
    expect(plan.updatedToml, isNot(contains('action = "shell"')));
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
action = "bash"
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

  test('providers / models 写入并可解析', () {
    const OpenCodeImport imported = OpenCodeImport(
      providers: <ImportedProvider>[
        ImportedProvider(
          name: 'acme',
          baseUrl: 'https://acme.example/v1',
          type: 'openai',
          credentialKey: 'ACME_KEY',
          models: <ImportedModel>[
            ImportedModel(
              model: 'gpt-x',
              displayName: 'GPT X',
              maxContext: 128000,
            ),
          ],
        ),
      ],
    );

    final OpenCodeImportPlan plan = planOpenCodeImport(
      toml: '',
      import: imported,
    );

    _expectParseable(plan.updatedToml);
    expect(plan.updatedToml, contains('[providers.acme]'));
    expect(plan.updatedToml, contains('base_url = "https://acme.example/v1"'));
    expect(plan.updatedToml, contains('credential_key = "ACME_KEY"'));
    expect(plan.updatedToml, contains('[models."acme/gpt-x"]'));
    expect(plan.updatedToml, contains('max_context_size = 128000'));
    expect(plan.added, hasLength(2));
  });

  test('已有同名 provider 时整组跳过', () {
    const String existing = '''
[providers.acme]
base_url = "https://old.example/v1"
type = "openai"
''';

    final OpenCodeImportPlan plan = planOpenCodeImport(
      toml: existing,
      import: const OpenCodeImport(
        providers: <ImportedProvider>[
          ImportedProvider(
            name: 'acme',
            baseUrl: 'https://new.example/v1',
            type: 'openai',
            apiKey: 'x',
          ),
        ],
      ),
    );

    expect(plan.updatedToml, contains('https://old.example/v1'));
    expect(plan.updatedToml, isNot(contains('new.example')));
    expect(plan.skipped.join('\n'), contains('acme'));
  });

  test('references 写入并可解析', () {
    const OpenCodeImport imported = OpenCodeImport(
      references: <ImportedReference>[
        ImportedReference(
          name: 'docs',
          path: '/tmp/product-docs',
          description: '产品文档',
        ),
      ],
    );

    final OpenCodeImportPlan plan = planOpenCodeImport(
      toml: '',
      import: imported,
    );

    _expectParseable(plan.updatedToml);
    expect(plan.updatedToml, contains('[references.docs]'));
    expect(plan.updatedToml, contains('path = "/tmp/product-docs"'));
    expect(plan.updatedToml, contains('description = "产品文档"'));
    expect(plan.added, <String>['reference docs']);
  });

  test('非法 TOML 抛 FormatException', () {
    expect(
      () => planOpenCodeImport(toml: '[bad', import: _import()),
      throwsA(isA<FormatException>()),
    );
  });
}

/// `nava import opencode`：dry-run、--write、来源开关与跳过。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

Directory _temp() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-oc-cli-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

String _path(Directory root, String relative) =>
    '${root.path}${Platform.pathSeparator}'
    '${relative.replaceAll('/', Platform.pathSeparator)}';

void _write(String path, String content) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

class _Fixture {
  _Fixture() {
    home = _temp();
    project = _temp();
    config = _path(home, '.nava/config.toml');
    _write(
      _path(home, '.config/opencode/opencode.jsonc'),
      '''
{
  // 全局模型
  "model": "global/model",
  "mcp": {
    "servers": {
      "global-fs": { "type": "local", "command": ["npx", "-y", "fs"] },
    },
  },
}
''',
    );
    _write(
      _path(project, 'opencode.json'),
      '''
{
  "default_agent": "plan",
  "permissions": [
    { "action": "bash", "resource": "git push *", "effect": "ask" },
  ],
  "instructions": ["CONTRIBUTING.md"],
  "mcp": {
    "servers": {
      "project-remote": {
        "type": "remote",
        "url": "https://project.example/mcp",
      },
    },
  },
}
''',
    );
  }

  late final Directory home;
  late final Directory project;
  late final String config;
  final StringBuffer out = StringBuffer();
  final StringBuffer err = StringBuffer();

  Future<int> run(List<String> args) => runImportCli(
    args,
    out: out,
    err: err,
    homeDir: home.path,
  );

  List<String> baseArgs() => <String>[
    'opencode',
    '--config',
    config,
    '--workdir',
    project.path,
  ];
}

void main() {
  test('缺省 dry-run 不写文件，只打印片段', () async {
    final _Fixture fixture = _Fixture();

    final int code = await fixture.run(fixture.baseArgs());

    expect(code, 0);
    expect(File(fixture.config).existsSync(), isFalse);
    expect(fixture.out.toString(), contains('将新增'));
    expect(fixture.out.toString(), contains('[llm]'));
    expect(fixture.out.toString(), contains('[mcp.servers.global-fs]'));
    expect(fixture.out.toString(), contains('[mcp.servers.project-remote]'));
  });

  test('--write 写入后 loadConfig 可解析，字段完整', () async {
    final _Fixture fixture = _Fixture();

    final int code = await fixture.run(<String>[
      ...fixture.baseArgs(),
      '--write',
    ]);

    expect(code, 0);
    final ConatusCodeConfig config = loadConfig(path: fixture.config);
    expect(config.llm.defaultModel, 'global/model');
    expect(config.agent.defaultAgent, 'plan');
    expect(
      config.mcp.servers.map((McpServerSpec spec) => spec.name),
      containsAll(<String>['global-fs', 'project-remote']),
    );
    expect(config.permissions.rules.single.action, 'shell');
    expect(config.permissions.rules.single.resource, 'git push *');
    expect(config.instructions, <String>['CONTRIBUTING.md']);
    expect(fixture.out.toString(), contains('已写入'));
  });

  test('已有 model 不被覆盖，并列出跳过原因', () async {
    final _Fixture fixture = _Fixture();
    _write(
      fixture.config,
      '[llm]\ndefault_model = "keep/me"\n',
    );

    final int code = await fixture.run(<String>[
      ...fixture.baseArgs(),
      '--write',
    ]);

    expect(code, 0);
    final ConatusCodeConfig config = loadConfig(path: fixture.config);
    expect(config.llm.defaultModel, 'keep/me');
    expect(fixture.err.toString(), contains('model（已有 default_model）'));
  });

  test('--global-only 只导入全局配置', () async {
    final _Fixture fixture = _Fixture();

    final int code = await fixture.run(<String>[
      ...fixture.baseArgs(),
      '--global-only',
      '--write',
    ]);

    expect(code, 0);
    final ConatusCodeConfig config = loadConfig(path: fixture.config);
    expect(config.llm.defaultModel, 'global/model');
    expect(config.agent.defaultAgent, 'build');
    expect(config.mcp.servers.single.name, 'global-fs');
  });

  test('没有 opencode 配置时正常退出并提示', () async {
    final Directory empty = _temp();
    final _Fixture fixture = _Fixture();
    fixture.out.clear();
    fixture.err.clear();

    final int code = await fixture.run(<String>[
      'opencode',
      '--config',
      fixture.config,
      '--workdir',
      empty.path,
      '--project-only',
    ]);

    expect(code, 0);
    expect(fixture.out.toString(), contains('没有找到 opencode.json(c)'));
  });

  test('互斥参数与未知参数返回 2', () async {
    final _Fixture fixture = _Fixture();

    final int code = await fixture.run(<String>[
      'opencode',
      '--global-only',
      '--project-only',
    ]);

    expect(code, 2);
    expect(fixture.err.toString(), contains('不能同时使用'));
    expect(await fixture.run(<String>['opencode', '--bogus']), 2);
  });

  test('拒绝写入 .opencode 只读目录', () async {
    final _Fixture fixture = _Fixture();
    final String protected = _path(fixture.home, '.opencode/config.toml');

    final int code = await fixture.run(<String>[
      'opencode',
      '--config',
      protected,
      '--workdir',
      fixture.project.path,
      '--write',
    ]);

    expect(code, 2);
    expect(File(protected).existsSync(), isFalse);
    expect(fixture.err.toString(), contains('写入失败'));
  });

  test('JSON agents / commands 物化为 .nava 定义并被注册表发现', () async {
    final _Fixture fixture = _Fixture();
    _write(
      _path(fixture.project, 'opencode.json'),
      '''
{
  "agents": {
    "reviewer": {
      "description": "Review changes",
      "mode": "subagent",
      "system": "Review the diff.",
      "permissions": [
        { "action": "edit", "resource": "*", "effect": "deny" },
      ],
    },
  },
  "commands": {
    "audit": {
      "description": "Audit",
      "template": "Audit the current changes.",
    },
  },
}
''',
    );

    final int code = await fixture.run(<String>[
      ...fixture.baseArgs(),
      '--project-only',
      '--write',
    ]);

    expect(code, 0);
    final String agentPath = _path(
      fixture.project,
      '.nava/agents/reviewer.md',
    );
    final String commandPath = _path(
      fixture.project,
      '.nava/commands/audit.md',
    );
    expect(File(agentPath).existsSync(), isTrue);
    expect(File(commandPath).existsSync(), isTrue);

    final AgentRegistry agents = await AgentRegistry.load(
      workdir: fixture.project.path,
      home: fixture.home.path,
    );
    final AgentDefinition? reviewer = agents.byId('reviewer');
    expect(reviewer, isNotNull);
    expect(reviewer!.system, 'Review the diff.');
    expect(reviewer.mode, AgentMode.subagent);
    expect(reviewer.permissions.single.action, 'edit');

    final CommandRegistry commands = await CommandRegistry.load(
      workdir: fixture.project.path,
      home: fixture.home.path,
    );
    expect(commands.byName('audit')!.template, 'Audit the current changes.');
  });

  test('定义文件 dry-run 不落盘，但打印目标与内容', () async {
    final _Fixture fixture = _Fixture();
    _write(
      _path(fixture.project, 'opencode.json'),
      '{"agents":{"reviewer":{"system":"Review the diff."}}}',
    );

    final int code = await fixture.run(<String>[
      ...fixture.baseArgs(),
      '--project-only',
    ]);

    expect(code, 0);
    expect(
      File(_path(fixture.project, '.nava/agents/reviewer.md')).existsSync(),
      isFalse,
    );
    expect(fixture.out.toString(), contains('.nava/agents/reviewer.md'));
    expect(fixture.out.toString(), contains('Review the diff.'));
  });
}

/// OpenCode JSON agents / commands 映射与物化文件。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

Directory _temp() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-oc-def-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

String _path(Directory root, String relative) =>
    '${root.path}${Platform.pathSeparator}'
    '${relative.replaceAll('/', Platform.pathSeparator)}';

OpenCodeImport _build(List<OpenCodeDocument> docs) => buildOpenCodeImport(
  OpenCodeSources(documents: docs, warnings: const <String>[]),
);

void main() {
  test('agents / commands 映射字段、模型变体与不支持字段告警', () {
    final OpenCodeImport imported = _build(<OpenCodeDocument>[
      const OpenCodeDocument(
        path: '/tmp/project/opencode.json',
        values: <String, Object?>{
          'agents': <String, Object?>{
            'reviewer': <String, Object?>{
              'description': 'Review changes',
              'mode': 'subagent',
              'model': 'anthropic/claude#high',
              'steps': 4,
              'system': 'Review the diff.',
              'permissions': <Object?>[
                <String, Object?>{
                  'action': 'edit',
                  'resource': '*',
                  'effect': 'deny',
                },
              ],
              'hidden': true,
            },
          },
          'commands': <String, Object?>{
            'audit': <String, Object?>{
              'template': r'Audit $ARGUMENTS',
              'description': 'Audit changes',
              'agent': 'reviewer',
              'model': 'anthropic/claude#low',
              'subagent': true,
            },
          },
        },
      ),
    ]);

    final ImportedAgent agent = imported.agents.single;
    expect(agent.id, 'reviewer');
    expect(agent.mode, 'subagent');
    expect(agent.model, 'anthropic/claude');
    expect(agent.steps, 4);
    expect(agent.system, 'Review the diff.');
    expect(agent.permissions.single.action, 'edit');

    final ImportedCommand command = imported.commands.single;
    expect(command.name, 'audit');
    expect(command.template, r'Audit $ARGUMENTS');
    expect(command.agent, 'reviewer');
    expect(command.model, 'anthropic/claude');
    expect(command.subagent, isTrue);

    final String warnings = imported.warnings.join('\n');
    expect(warnings, contains('#variant'));
    expect(warnings, contains('hidden'));
  });

  test('同名 agent 由后者覆盖，global 标记跟随最后定义', () {
    final OpenCodeImport imported = _build(<OpenCodeDocument>[
      const OpenCodeDocument(
        path: '/home/.config/opencode/opencode.json',
        global: true,
        values: <String, Object?>{
          'agents': <String, Object?>{
            'shared': <String, Object?>{'system': 'global'},
          },
        },
      ),
      const OpenCodeDocument(
        path: '/tmp/project/opencode.json',
        values: <String, Object?>{
          'agents': <String, Object?>{
            'shared': <String, Object?>{'system': 'project'},
          },
        },
      ),
    ]);

    final ImportedAgent agent = imported.agents.single;
    expect(agent.system, 'project');
    expect(agent.global, isFalse);
  });

  test('disabled / 缺 template / 不安全 ID 的跳过与告警', () {
    final OpenCodeImport imported = _build(<OpenCodeDocument>[
      const OpenCodeDocument(
        path: '/tmp/opencode.json',
        values: <String, Object?>{
          'agents': <String, Object?>{
            'off': <String, Object?>{'disabled': true},
            'empty': <String, Object?>{},
            '../evil': <String, Object?>{'system': 'x'},
          },
          'commands': <String, Object?>{
            'none': <String, Object?>{'description': 'no template'},
          },
        },
      ),
    ]);

    expect(imported.agents.map((ImportedAgent agent) => agent.id), <String>[
      '../evil',
    ]);
    expect(imported.commands, isEmpty);
    final String warnings = imported.warnings.join('\n');
    expect(warnings, contains('off'));
    expect(warnings, contains('empty'));
    expect(warnings, contains('none'));
  });

  test('物化路径：项目 agents/commands 与全局 agent；已有文件跳过', () {
    final Directory workdir = _temp();
    final Directory home = _temp();
    final OpenCodeImport imported = _build(<OpenCodeDocument>[
      const OpenCodeDocument(
        path: '/home/.config/opencode/opencode.json',
        global: true,
        values: <String, Object?>{
          'agents': <String, Object?>{
            'global-agent': <String, Object?>{'system': 'global body'},
          },
        },
      ),
      const OpenCodeDocument(
        path: '/tmp/project/opencode.json',
        values: <String, Object?>{
          'agents': <String, Object?>{
            'reviewer': <String, Object?>{
              'description': 'Review',
              'system': 'body',
            },
          },
          'commands': <String, Object?>{
            'audit': <String, Object?>{'template': 'Audit'},
          },
        },
      ),
    ]);

    final DefinitionFilePlan plan = planOpenCodeDefinitionFiles(
      import: imported,
      workdir: workdir.path,
      homeDir: home.path,
    );

    expect(plan.files, hasLength(3));
    expect(
      plan.files.map((ImportedDefinitionFile file) => file.path),
      containsAll(<String>[
        _path(home, '.nava/agents/global-agent.md'),
        _path(workdir, '.nava/agents/reviewer.md'),
        _path(workdir, '.nava/commands/audit.md'),
      ]),
    );
    final ImportedDefinitionFile agentFile = plan.files.firstWhere(
      (ImportedDefinitionFile file) => file.label == 'agent reviewer',
    );
    expect(agentFile.content, startsWith('---\n'));
    expect(agentFile.content, contains('description: "Review"'));
    expect(agentFile.content, endsWith('body\n'));
  });

  test('已有文件与不安全路径跳过', () {
    final Directory workdir = _temp();
    final Directory home = _temp();
    final OpenCodeImport imported = _build(<OpenCodeDocument>[
      const OpenCodeDocument(
        path: '/tmp/project/opencode.json',
        values: <String, Object?>{
          'agents': <String, Object?>{
            'exists': <String, Object?>{'system': 'x'},
            '../evil': <String, Object?>{'system': 'x'},
          },
        },
      ),
    ]);
    final String existing = _path(workdir, '.nava/agents/exists.md');
    File(existing)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('keep');

    final DefinitionFilePlan plan = planOpenCodeDefinitionFiles(
      import: imported,
      workdir: workdir.path,
      homeDir: home.path,
    );

    expect(plan.files, isEmpty);
    expect(plan.skipped.join('\n'), contains('exists'));
    expect(plan.skipped.join('\n'), contains('不安全'));
  });
}

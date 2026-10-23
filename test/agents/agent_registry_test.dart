/// Agent 发现：四层优先级、嵌套 ID、内置 Agent、hidden 与默认选择。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart' show PermissionEffect;
import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

/// 写入一份带 [body] 正文的 Agent 文件，frontmatter 由 [frontmatter] 决定。
void writeAgent(
  Directory root,
  String name, {
  String frontmatter = '',
  String body = 'body',
}) {
  final File file = File('${root.path}/$name');
  file.parent.createSync(recursive: true);
  final String header = frontmatter.trim().isEmpty
      ? ''
      : '---\n${frontmatter.trim()}\n---\n';
  file.writeAsStringSync('$header$body');
}

/// 目录内相对路径 + 内容的稳定快照（只读遍历）。
List<String> snapshotDirectory(Directory root) {
  final List<String> entries = <String>[
    for (final FileSystemEntity entity in root.listSync(
      recursive: true,
      followLinks: false,
    ))
      if (entity is File)
        '${entity.path.substring(root.path.length)}:${entity.readAsStringSync()}',
  ]..sort();
  return entries;
}

void main() {
  late Directory home;
  late Directory work;

  setUp(() {
    home = Directory.systemTemp.createTempSync('nava-agent-home');
    work = Directory.systemTemp.createTempSync('nava-agent-work');
    addTearDown(() {
      home.deleteSync(recursive: true);
      work.deleteSync(recursive: true);
    });
  });

  Future<AgentRegistry> load({String? defaultId}) => AgentRegistry.load(
    workdir: work.path,
    home: home.path,
    defaultId: defaultId,
  );

  test('内置 Agent 的模式、只读规则与工具', () async {
    final AgentRegistry registry = await load();

    expect(registry.byId('build')!.mode, AgentMode.primary);
    expect(registry.byId('build')!.permissions, isEmpty);
    expect(registry.byId('plan')!.mode, AgentMode.primary);
    expect(registry.byId('plan')!.permissions.single.action, 'edit');
    expect(
      registry.byId('plan')!.permissions.single.effect,
      PermissionEffect.deny,
    );
    expect(registry.byId('general')!.mode, AgentMode.subagent);
    expect(registry.byId('general')!.permissions, isEmpty);
    expect(registry.byId('explore')!.mode, AgentMode.subagent);
    expect(
      registry.byId('explore')!.permissions.single.effect,
      PermissionEffect.deny,
    );
    expect(
      registry.byId('explore')!.tools,
      containsAll(<String>['read_file', 'rg', 'glob', 'web_search']),
    );
  });

  test('优先级：项目 .nava 覆盖全局 .opencode', () async {
    writeAgent(
      Directory('${home.path}/.config/opencode/agents'),
      'reviewer.md',
      body: 'global opencode',
    );
    writeAgent(
      Directory('${home.path}/.nava/agents'),
      'reviewer.md',
      body: 'global nava',
    );
    writeAgent(
      Directory('${work.path}/.opencode/agents'),
      'reviewer.md',
      body: 'project opencode',
    );
    writeAgent(
      Directory('${work.path}/.nava/agents'),
      'reviewer.md',
      body: 'project nava',
    );

    final AgentRegistry registry = await load();

    expect(registry.byId('reviewer')!.system, 'project nava');
    expect(registry.byId('reviewer')!.sourcePath, contains('.nava'));
  });

  test('项目 .opencode 覆盖全局 .nava', () async {
    writeAgent(
      Directory('${home.path}/.nava/agents'),
      'reviewer.md',
      body: 'global nava',
    );
    writeAgent(
      Directory('${work.path}/.opencode/agents'),
      'reviewer.md',
      body: 'project opencode',
    );

    expect((await load()).byId('reviewer')!.system, 'project opencode');
  });

  test('全局 .nava 覆盖全局 .opencode', () async {
    writeAgent(
      Directory('${home.path}/.config/opencode/agents'),
      'reviewer.md',
      body: 'global opencode',
    );
    writeAgent(
      Directory('${home.path}/.nava/agents'),
      'reviewer.md',
      body: 'global nava',
    );

    expect((await load()).byId('reviewer')!.system, 'global nava');
  });

  test('嵌套目录形成 team/reviewer ID', () async {
    writeAgent(
      Directory('${work.path}/.nava/agents/team'),
      'reviewer.md',
      frontmatter: 'mode: subagent',
      body: 'nested',
    );

    final AgentRegistry registry = await load();

    expect(registry.byId('team/reviewer')!.system, 'nested');
    expect(registry.byId('team/reviewer')!.mode, AgentMode.subagent);
  });

  test('内置 Agent 可被同名自定义覆盖', () async {
    writeAgent(
      Directory('${work.path}/.nava/agents'),
      'build.md',
      frontmatter: 'description: custom build',
      body: 'CUSTOM BUILD',
    );

    final AgentRegistry registry = await load();

    expect(registry.byId('build')!.system, 'CUSTOM BUILD');
    expect(registry.byId('build')!.description, 'custom build');
  });

  test('hidden Agent 不在 visible，但仍可按 ID 解析', () async {
    writeAgent(
      Directory('${work.path}/.nava/agents'),
      'hidden.md',
      frontmatter: 'hidden: true\nmode: subagent',
      body: 'hidden body',
    );
    writeAgent(
      Directory('${work.path}/.nava/agents'),
      'shown.md',
      frontmatter: 'mode: subagent',
      body: 'shown body',
    );

    final AgentRegistry registry = await load();

    expect(
      registry.visible.any((AgentDefinition a) => a.id == 'hidden'),
      isFalse,
    );
    expect(
      registry.subagents.any((AgentDefinition a) => a.id == 'hidden'),
      isFalse,
    );
    expect(registry.byId('hidden')!.system, 'hidden body');
    expect(
      registry.visible.any((AgentDefinition a) => a.id == 'shown'),
      isTrue,
    );
  });

  test('visible 按 ID 稳定排序且包含 primary 与 subagent', () async {
    writeAgent(
      Directory('${work.path}/.nava/agents'),
      'zulu.md',
      frontmatter: 'mode: primary',
    );
    writeAgent(
      Directory('${work.path}/.nava/agents'),
      'alpha.md',
      frontmatter: 'mode: all',
    );

    final AgentRegistry registry = await load();

    expect(registry.visible.map((AgentDefinition a) => a.id), <String>[
      'alpha',
      'build',
      'explore',
      'general',
      'plan',
      'zulu',
    ]);
    expect(
      registry.subagents.map((AgentDefinition a) => a.id),
      containsAll(<String>['alpha', 'explore', 'general']),
    );
  });

  test('默认 Agent：配置值优先，未知值回退 build', () async {
    writeAgent(
      Directory('${work.path}/.nava/agents'),
      'custom.md',
      frontmatter: 'mode: primary',
    );

    expect((await load()).defaultAgent.id, 'build');
    expect((await load(defaultId: 'plan')).defaultAgent.id, 'plan');
    expect((await load(defaultId: 'custom')).defaultAgent.id, 'custom');
    expect((await load(defaultId: 'missing')).defaultAgent.id, 'build');
  });

  test('无效文件跳过且其余 Agent 照常加载，并记录原因', () async {
    writeAgent(Directory('${work.path}/.nava/agents'), 'good.md', body: 'good');
    writeAgent(
      Directory('${work.path}/.nava/agents'),
      'bad.md',
      frontmatter: 'mode: helper',
      body: 'bad',
    );

    final AgentRegistry registry = await load();

    expect(registry.byId('good')!.system, 'good');
    expect(registry.byId('bad'), isNull);
    expect(registry.warnings, hasLength(1));
    expect(registry.warnings.single, contains('bad.md'));
    expect(registry.warnings.single, contains('mode'));
  });

  test('只发现 .md 文件（扩展名大小写不敏感）', () async {
    final Directory root = Directory('${work.path}/.nava/agents');
    writeAgent(root, 'yes.md', body: 'yes');
    writeAgent(root, 'upper.MD', body: 'upper');
    writeAgent(root, 'no.txt', body: 'no');

    final AgentRegistry registry = await load();

    expect(registry.byId('yes'), isNotNull);
    expect(registry.byId('upper'), isNotNull);
    expect(registry.byId('no'), isNull);
  });

  test('加载不修改 .opencode（文件与内容保持不变）', () async {
    final Directory opencode = Directory('${work.path}/.opencode/agents');
    writeAgent(opencode, 'reviewer.md', body: 'review body');
    writeAgent(opencode, 'team/deep.md', body: 'deep body');
    final List<String> before = snapshotDirectory(opencode);

    await load();

    expect(snapshotDirectory(opencode), before);
  });
}

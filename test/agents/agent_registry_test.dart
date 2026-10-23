/// Agent 发现：四层优先级、嵌套 ID 与内置 Agent 覆盖。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart' show PermissionEffect;
import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

import 'agent_test_support.dart';

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
}

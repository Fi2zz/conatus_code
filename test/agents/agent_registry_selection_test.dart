/// Agent 选择：hidden 过滤、visible/subagents 排序与默认 Agent 回退。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

import 'agent_test_support.dart';

void main() {
  late Directory home;
  late Directory work;

  setUp(() {
    home = Directory.systemTemp.createTempSync('nava-agent-select-home');
    work = Directory.systemTemp.createTempSync('nava-agent-select-work');
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

  test('默认 Agent 不接受 subagent-only，回退并提示', () async {
    writeAgent(
      Directory('${work.path}/.nava/agents'),
      'reviewer.md',
      frontmatter: 'mode: subagent',
    );

    final AgentRegistry registry = await load(defaultId: 'reviewer');

    expect(registry.defaultAgent.id, 'build');
    expect(registry.warnings.single, contains('subagent'));
    expect(registry.warnings.single, contains('reviewer'));
  });
}

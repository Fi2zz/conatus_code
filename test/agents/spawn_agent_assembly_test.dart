/// nava 侧 resolver：把 AgentRegistry 定义映射为 spawn_agent 的 profile。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/providers.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

import 'agent_test_support.dart';

void main() {
  late Directory workdir;
  late Directory home;

  setUp(() {
    workdir = Directory.systemTemp.createTempSync('nava-resolver-work-');
    home = Directory.systemTemp.createTempSync('nava-resolver-home-');
  });

  tearDown(() {
    workdir.deleteSync(recursive: true);
    home.deleteSync(recursive: true);
  });

  Future<AgentRegistry> load() =>
      AgentRegistry.load(workdir: workdir.path, home: home.path);

  test('explore 映射为只读并保留只读工具白名单', () async {
    final AgentProfileResolver resolver = AgentProfileResolver(
      registry: await load(),
    );
    final SubAgentProfile profile = (await resolver.resolve('explore'))!;

    expect(profile.permissionMode, SubAgentPermission.readonly);
    expect(profile.tools, contains('read_file'));
    expect(profile.tools, isNot(contains('write_file')));
    expect(
      profile.permissions,
      contains(
        predicate<PermissionRule>(
          (PermissionRule rule) =>
              rule.action == 'edit' && rule.effect == PermissionEffect.deny,
        ),
      ),
    );
    expect(profile.llm, isNull);
  });

  test('plan 映射为只读并拒绝 edit', () async {
    final AgentProfileResolver resolver = AgentProfileResolver(
      registry: await load(),
    );
    final SubAgentProfile profile = (await resolver.resolve('plan'))!;

    expect(profile.permissionMode, SubAgentPermission.readonly);
    expect(
      profile.permissions,
      contains(
        predicate<PermissionRule>(
          (PermissionRule rule) =>
              rule.action == 'edit' && rule.effect == PermissionEffect.deny,
        ),
      ),
    );
  });

  test('general 与自定义 Agent 继承宿主权限', () async {
    writeAgent(
      Directory('${workdir.path}/.nava/agents'),
      'reviewer.md',
      frontmatter: 'description: review\nmode: subagent\nsteps: 3',
      body: 'REVIEW ONLY',
    );
    final AgentProfileResolver resolver = AgentProfileResolver(
      registry: await load(),
    );

    expect(
      (await resolver.resolve('general'))!.permissionMode,
      SubAgentPermission.inherit,
    );
    final SubAgentProfile custom = (await resolver.resolve('reviewer'))!;
    expect(custom.permissionMode, SubAgentPermission.inherit);
    expect(custom.system, 'REVIEW ONLY');
    expect(custom.steps, 3);
  });

  test('provider/model 构造模型，未知 provider 回退 null', () async {
    writeAgent(
      Directory('${workdir.path}/.nava/agents'),
      'models.md',
      frontmatter: 'mode: subagent\nmodel: acme/gpt-x',
    );
    writeAgent(
      Directory('${workdir.path}/.nava/agents'),
      'broken.md',
      frontmatter: 'mode: subagent\nmodel: nope/gpt-x',
    );
    final ProviderRegistry providers = ProviderRegistry(
      profiles: <ProviderProfile>[
        const ProviderProfile(
          name: 'acme',
          baseUrl: 'https://example.test/v1',
          models: <String>['gpt-x'],
        ),
      ],
    );
    final AgentProfileResolver resolver = AgentProfileResolver(
      registry: await load(),
      providers: providers,
    );

    final SubAgentProfile custom = (await resolver.resolve('models'))!;
    expect(custom.llm, isA<OpenAiCompatibleProvider>());
    expect((custom.llm! as OpenAiCompatibleProvider).model, 'gpt-x');
    expect((await resolver.resolve('broken'))!.llm, isNull);
  });

  test('OpenCode tools 开关映射为 disabledTools', () async {
    writeAgent(
      Directory('${workdir.path}/.nava/agents'),
      'tools.md',
      frontmatter:
          'mode: subagent\ntools:\n  task: false\n  list: false\n  todowrite: false',
    );
    final AgentProfileResolver resolver = AgentProfileResolver(
      registry: await load(),
    );

    final SubAgentProfile profile = (await resolver.resolve('tools'))!;
    expect(
      profile.disabledTools,
      containsAll(<String>['spawn_agent', 'list_files', 'update_plan']),
    );
  });

  test('未知 Agent 返回 null，不静默降级', () async {
    final AgentProfileResolver resolver = AgentProfileResolver(
      registry: await load(),
    );
    expect(await resolver.resolve('missing'), isNull);
  });
}

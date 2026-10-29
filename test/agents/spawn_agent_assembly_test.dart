/// nava 侧 resolver：把 AgentRegistry 定义映射为 task 的 profile。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/providers.dart';
import 'package:conatus_code/tui.dart';
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
    expect(profile.tools, contains('read'));
    expect(profile.tools, isNot(contains('write')));
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
    expect(
      identical(custom.llm, (await resolver.resolve('models'))!.llm),
      isTrue,
      reason: '同一 provider/model 复用同一个 provider 实例',
    );
    expect((await resolver.resolve('broken'))!.llm, isNull);
    expect(resolver.warnings, contains(contains('nope/gpt-x')));
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
      containsAll(<String>['task', 'list', 'todowrite']),
    );
  });

  test('未知 Agent 返回 null，不静默降级', () async {
    final AgentProfileResolver resolver = AgentProfileResolver(
      registry: await load(),
    );
    expect(await resolver.resolve('missing'), isNull);
  });

  test('primary 模式 Agent 可按 ID spawn（plan 依赖该行为）', () async {
    writeAgent(
      Directory('${workdir.path}/.nava/agents'),
      'primary.md',
      frontmatter: 'mode: primary',
      body: 'PRIMARY',
    );
    final AgentProfileResolver resolver = AgentProfileResolver(
      registry: await load(),
    );

    expect((await resolver.resolve('primary'))!.system, 'PRIMARY');
    expect((await resolver.resolve('plan'))!.id, 'plan');
  });

  test('tui_app 装配把 AgentRegistry 解析器注入 task', () async {
    writeAgent(
      Directory('${workdir.path}/.nava/agents'),
      'wired.md',
      frontmatter: 'mode: subagent',
      body: 'WIRED',
    );
    final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
      baseDir: home.path,
      sessionDir: home.path,
      memoryFile: '${home.path}/memory.json',
      webTools: false,
      skills: false,
      llm: FallbackLlm(const <LlmProvider>[]),
      workdir: workdir.path,
      interactive: false,
    );
    addTearDown(runtime.dispose);

    final SpawnAgentTool tool =
        runtime.tools.get('task')! as SpawnAgentTool;
    expect(tool.profileResolver, isA<AgentProfileResolver>());
    final SubAgentProfile? profile = await tool.profileResolver!.resolve(
      'wired',
    );
    expect(profile?.system, 'WIRED');
  });
}

/// 端到端：TUI「总是允许」→ 写入项目权限文件 → 作用域即时更新。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

void main() {
  test('总是允许写入项目文件并更新根作用域', () async {
    final Directory dir = Directory.systemTemp.createTempSync('perm-flow');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String sep = Platform.pathSeparator;
    final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
      baseDir: dir.path,
      sessionDir: dir.path,
      memoryFile: '${dir.path}${sep}memory.json',
      webTools: false,
      skills: false,
      llm: FallbackLlm(const <LlmProvider>[]),
    );
    addTearDown(runtime.dispose);
    final ConatusTuiController controller = runtime.createController(
      onExit: () {},
    );
    await controller.start();

    final TuiPermissionGate gate = runtime.app.require<TuiPermissionGate>(
      'approval',
    );
    final Future<bool> pending = gate.request(
      ApprovalRequest(
        id: 'r1',
        toolName: 'run_command',
        action: 'shell',
        resources: <String>['git status'],
        arguments: <String, Object?>{'command': 'git status'},
      ),
    );
    gate.choice
      ..move(1) // 允许一次 / 总是允许 / 拒绝
      ..confirm();
    expect(await pending, isTrue);
    // 落盘是异步的（回调类型为 void）：轮询到作用域更新后再断言（文件写入
    // 先于 `_publish`，作用域更新即表示两件事都完成）。
    final PermissionScopeSlot slot = runtime.app.require<PermissionScopeSlot>(
      kPermissionScopeService,
    );
    for (
      var attempt = 0;
      attempt < 200 && slot.current.rules.isEmpty;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final List<PermissionRule> saved = await PermissionStore(
      '${dir.path}${sep}permissions.json',
    ).load();
    expect(saved.single.action, 'shell');
    expect(saved.single.resource, 'git *');

    final PermissionScope scope = slot.current;
    expect(scope.rules.map((PermissionRule r) => r.resource), <String>[
      'git *',
    ]);
    expect(scope.agentId, 'build');
  });

  test('项目文件损坏时保留会话放行并提示未保存', () async {
    final Directory dir = Directory.systemTemp.createTempSync('perm-flow');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String sep = Platform.pathSeparator;
    File('${dir.path}${sep}permissions.json').writeAsStringSync('{broken');
    final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
      baseDir: dir.path,
      sessionDir: dir.path,
      memoryFile: '${dir.path}${sep}memory.json',
      webTools: false,
      skills: false,
      llm: FallbackLlm(const <LlmProvider>[]),
    );
    addTearDown(runtime.dispose);
    final ConatusTuiController controller = runtime.createController(
      onExit: () {},
    );
    await controller.start();

    await controller.rememberPermissionRules(
      const <PermissionRule>[
        PermissionRule(
          action: 'shell',
          resource: 'git *',
          effect: PermissionEffect.allow,
          source: 'project',
        ),
      ],
      <String>['git status'],
    );

    expect(controller.transcript.messages.last.text, contains('权限规则未保存'));
    expect(
      runtime.app
          .require<PermissionScopeSlot>(kPermissionScopeService)
          .current
          .rules,
      isEmpty,
    );
    expect(
      File('${dir.path}${sep}permissions.json').readAsStringSync(),
      '{broken',
    );
  });

  test('绑定会话时清空会话规则层（config → project → session）', () async {
    final Directory dir = Directory.systemTemp.createTempSync('perm-flow');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String sep = Platform.pathSeparator;
    final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
      baseDir: dir.path,
      sessionDir: dir.path,
      memoryFile: '${dir.path}${sep}memory.json',
      webTools: false,
      skills: false,
      llm: FallbackLlm(const <LlmProvider>[]),
    );
    addTearDown(runtime.dispose);
    final PermissionWiring wiring =
        runtime.app.require<PermissionWiring>('permissionWiring');
    wiring.setSessionRules(const <PermissionRule>[
      PermissionRule(
        action: 'shell',
        resource: 'old *',
        effect: PermissionEffect.deny,
        source: 'session',
      ),
    ]);
    expect(wiring.slot.current.rules, hasLength(1));

    final ConatusTuiController controller = runtime.createController(
      onExit: () {},
    );
    await controller.start();

    expect(wiring.slot.current.rules, isEmpty);
  });
}

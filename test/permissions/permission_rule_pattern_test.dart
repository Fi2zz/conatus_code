/// 「总是允许」的规则推导：只保存具体资源，绝不落盘通配 allow。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

ApprovalRequest _request({
  required String tool,
  String action = '',
  List<String> resources = const <String>[],
  List<String> pathArgs = const <String>[],
  String? rule,
}) => ApprovalRequest(
  id: 'r1',
  toolName: tool,
  description: '说明',
  action: action,
  resources: resources,
  pathArgs: pathArgs,
  rule: rule,
);

void main() {
  group('permissionRulesFor', () {
    test('shell 取命令前缀 + " *"', () {
      final List<PermissionRule> rules = permissionRulesFor(
        _request(
          tool: 'run_command',
          action: 'shell',
          resources: <String>['git push origin main'],
        ),
      );

      expect(rules.single.action, 'shell');
      expect(rules.single.resource, 'git *');
      expect(rules.single.effect, PermissionEffect.allow);
      expect(rules.single.source, 'project');
      expect(
        permissionPatternMatches(rules.single.resource, 'git status'),
        isTrue,
      );
    });

    test('路径工具保存具体路径（不放大到目录）', () {
      final List<PermissionRule> rules = permissionRulesFor(
        _request(
          tool: 'read_file',
          action: 'read',
          resources: <String>['/tmp/work/a.txt'],
        ),
      );
      expect(rules.single.action, 'read');
      expect(rules.single.resource, '/tmp/work/a.txt');
      expect(
        permissionPatternMatches(rules.single.resource, '/tmp/work/b.txt'),
        isFalse,
      );
    });

    test('多路径（apply_patch）每条资源一条规则', () {
      final List<PermissionRule> rules = permissionRulesFor(
        _request(
          tool: 'apply_patch',
          action: 'edit',
          resources: <String>['config/.env', 'src/a.dart'],
        ),
      );
      expect(rules.map((PermissionRule r) => r.resource), <String>[
        'config/.env',
        'src/a.dart',
      ]);
    });

    test('相对路径 / ~ 规范化后再保存', () {
      final List<PermissionRule> dot = permissionRulesFor(
        _request(
          tool: 'write_file',
          action: 'edit',
          resources: <String>['./src/deep/../a.dart'],
        ),
      );
      expect(dot.single.resource, 'src/a.dart');

      final List<PermissionRule> home = permissionRulesFor(
        _request(
          tool: 'write_file',
          action: 'edit',
          resources: <String>['~/secret.txt'],
        ),
      );
      final String expected = normalizePermissionPath('~/secret.txt');
      expect(home.single.resource, expected);
      expect(permissionPatternMatches(home.single.resource, expected), isTrue);
    });

    test('没有具体资源时不生成规则（MCP / question / 通配）', () {
      for (final String action in <String>[
        'fs_read_file',
        'question',
        'shell',
      ]) {
        expect(
          permissionRulesFor(
            _request(tool: 'x', action: action, resources: <String>['*']),
          ),
          isEmpty,
        );
      }
      expect(
        permissionRulesFor(
          _request(tool: 'read_file', action: 'read', resources: <String>['*']),
        ),
        isEmpty,
      );
    });

    test('请求未带 action 时按工具名映射', () {
      final List<PermissionRule> rules = permissionRulesFor(
        _request(tool: 'run_tests', resources: <String>['dart test']),
      );
      expect(rules.single.action, 'shell');
      expect(rules.single.resource, 'dart *');
    });
  });

  group('审批浮层展示', () {
    test('展示 action / resource / 命中规则', () async {
      final TuiChoicePrompt choice = TuiChoicePrompt();
      final TuiPermissionGate gate = TuiPermissionGate(choice: choice);

      final Future<bool> pending = gate.request(
        _request(
          tool: 'run_command',
          action: 'shell',
          resources: <String>['git push'],
          rule: 'PermissionRule(shell, git push *, deny)',
        ),
      );

      final String description = choice.request!.choices.first.description;
      expect(description, contains('shell'));
      expect(description, contains('git push'));
      expect(description, contains('PermissionRule'));

      choice.cancel();
      await pending;
    });

    test('总是允许展示并回调精确 pattern，同时保留会话放行', () async {
      final TuiChoicePrompt choice = TuiChoicePrompt();
      final List<PermissionRule> remembered = <PermissionRule>[];
      final List<String> resources = <String>[];
      final TuiPermissionGate gate = TuiPermissionGate(
        choice: choice,
        rememberRules: (List<PermissionRule> rules, List<String> approved) {
          remembered.addAll(rules);
          resources.addAll(approved);
        },
      );

      final Future<bool> first = gate.request(
        _request(
          tool: 'read_file',
          action: 'read',
          resources: <String>['/tmp/a.txt'],
        ),
      );
      final String description = choice.request!.choices[1].description;
      expect(description, contains('read /tmp/a.txt'));

      choice
        ..move(1)
        ..confirm();
      expect(await first, isTrue);

      expect(remembered.single.resource, '/tmp/a.txt');
      expect(resources, <String>['/tmp/a.txt']);
      expect(gate.alwaysAllowed, contains('read_file'));
      expect(await gate.request(_request(tool: 'read_file')), isTrue);
      expect(choice.open, isFalse);
    });

    test('apply_patch 总是允许保存每个目标路径', () async {
      final TuiChoicePrompt choice = TuiChoicePrompt();
      final List<PermissionRule> remembered = <PermissionRule>[];
      final TuiPermissionGate gate = TuiPermissionGate(
        choice: choice,
        rememberRules: (List<PermissionRule> rules, List<String> resources) {
          remembered.addAll(rules);
        },
      );

      final Future<bool> pending = gate.request(
        _request(
          tool: 'apply_patch',
          action: 'edit',
          resources: <String>['config/.env', 'src/a.dart'],
        ),
      );
      await pumpEventQueue();
      choice
        ..move(1)
        ..confirm();
      expect(await pending, isTrue);

      expect(remembered.map((PermissionRule r) => r.resource), <String>[
        'config/.env',
        'src/a.dart',
      ]);
    });

    test('没有具体资源时说明仅会话有效且不回调', () async {
      final TuiChoicePrompt choice = TuiChoicePrompt();
      var called = false;
      final TuiPermissionGate gate = TuiPermissionGate(
        choice: choice,
        rememberRules: (List<PermissionRule> rules, List<String> resources) {
          called = true;
        },
      );

      final Future<bool> pending = gate.request(
        _request(
          tool: 'fs__read_file',
          action: 'fs_read_file',
          resources: <String>['*'],
        ),
      );
      expect(choice.request!.choices[1].description, contains('仅本次会话'));

      choice
        ..move(1)
        ..confirm();
      expect(await pending, isTrue);
      expect(called, isFalse);
    });
  });
}

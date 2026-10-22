/// 「总是允许」的规则推导：shell 命令前缀、路径目录 glob、其余通配。
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
  group('permissionRuleFor', () {
    test('shell 取命令前缀 + " *"', () {
      final PermissionRule rule = permissionRuleFor(
        _request(
          tool: 'run_command',
          action: 'shell',
          resources: <String>['git push origin main'],
        ),
      );

      expect(rule.action, 'shell');
      expect(rule.resource, 'git *');
      expect(rule.effect, PermissionEffect.allow);
      expect(rule.source, 'project');
      expect(permissionPatternMatches(rule.resource, 'git status'), isTrue);
    });

    test('无参数命令退化为精确命令 + " *"', () {
      final PermissionRule rule = permissionRuleFor(
        _request(
          tool: 'run_command',
          action: 'shell',
          resources: <String>['ls'],
        ),
      );
      expect(rule.resource, 'ls *');
      expect(permissionPatternMatches(rule.resource, 'ls'), isTrue);
    });

    test('路径工具取父目录 + "/*"', () {
      final PermissionRule rule = permissionRuleFor(
        _request(
          tool: 'read_file',
          action: 'read_file',
          resources: <String>['/tmp/work/a.txt'],
          pathArgs: <String>['/tmp/work/a.txt'],
        ),
      );
      expect(rule.action, 'read_file');
      expect(rule.resource, '/tmp/work/*');
      expect(
        permissionPatternMatches(rule.resource, '/tmp/work/b.txt'),
        isTrue,
      );
    });

    test('相对路径取所在目录', () {
      final PermissionRule rule = permissionRuleFor(
        _request(
          tool: 'write_file',
          action: 'write_file',
          pathArgs: <String>['src/deep/a.dart'],
        ),
      );
      expect(rule.resource, 'src/deep/*');
    });

    test('MCP / 其他工具取动作 + 通配资源', () {
      final PermissionRule rule = permissionRuleFor(
        _request(
          tool: 'fs__read_file',
          action: 'fs_read_file',
          resources: <String>['*'],
        ),
      );
      expect(rule.action, 'fs_read_file');
      expect(rule.resource, '*');
    });

    test('请求未带 action 时按工具名映射', () {
      final PermissionRule rule = permissionRuleFor(
        _request(tool: 'run_tests', resources: <String>['dart test']),
      );
      expect(rule.action, 'shell');
      expect(rule.resource, 'dart *');
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

    test('总是允许回调收到推导出的规则并保留会话内放行', () async {
      final TuiChoicePrompt choice = TuiChoicePrompt();
      final List<PermissionRule> remembered = <PermissionRule>[];
      final TuiPermissionGate gate = TuiPermissionGate(
        choice: choice,
        rememberRule: remembered.add,
      );

      final Future<bool> first = gate.request(
        _request(
          tool: 'run_command',
          action: 'shell',
          resources: <String>['git status'],
        ),
      );
      choice
        ..move(1)
        ..confirm();
      expect(await first, isTrue);

      expect(remembered.single.resource, 'git *');
      expect(gate.alwaysAllowed, contains('run_command'));
      expect(await gate.request(_request(tool: 'run_command')), isTrue);
      expect(choice.open, isFalse);
    });
  });
}

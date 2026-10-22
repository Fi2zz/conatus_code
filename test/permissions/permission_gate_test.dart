/// 权限中间件：显式 deny、零配置兼容与 headless。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'permission_rig.dart';

void main() {
  group('显式 deny', () {
    test('never_ask（阈值 null）下仍然拒绝，执行体不运行', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'shell',
              resource: 'git push *',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('run_command', <String, Object?>{
          'command': 'git push origin main',
        }),
      );

      expect(result.isError, isTrue);
      expect(result.error!.code, 'PERMISSION_DENIED');
      expect(rig.runs, isEmpty);
    });

    test('headless 下显式 deny 依旧生效', () async {
      final PermissionRig rig = assemblePermissionRig(
        interactive: false,
        attachApproval: false,
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'shell',
              resource: 'rm *',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('run_command', <String, Object?>{'command': 'rm -rf x'}),
      );
      expect(result.error!.code, 'PERMISSION_DENIED');
      expect(rig.runs, isEmpty);
    });
  });

  group('零配置兼容', () {
    test('高危工具按阈值询问，批准后执行', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('run_command', <String, Object?>{'command': 'ls'}),
      );

      expect(result.isError, isFalse);
      expect(rig.gate.requests, hasLength(1));
      expect(rig.gate.requests.single.toolName, 'run_command');
      expect(rig.gate.requests.single.action, 'shell');
      expect(rig.runs, <String>['run_command']);
    });

    test('拒绝时返回 APPROVAL_DENIED 且不执行', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
        gate: PermissionGateStub(approved: false),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('run_command', <String, Object?>{'command': 'ls'}),
      );
      expect(result.error!.code, 'APPROVAL_DENIED');
      expect(rig.runs, isEmpty);
    });

    test('声明路径参数的低风险工具仍会询问（目录信任的前提）', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('read_file', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(result.isError, isFalse);
      expect(rig.gate.requests, hasLength(1));
      expect(rig.gate.requests.single.pathArgs, <String>['/tmp/a.txt']);
      expect(rig.gate.requests.single.resources, <String>['/tmp/a.txt']);
    });

    test('preapproved 覆盖路径时直接放行，不打扰用户', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
        gate: PermissionGateStub(trusted: true),
      );

      await rig.tools.call(
        permissionCall('read_file', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(rig.gate.requests, isEmpty);
      expect(rig.runs, <String>['read_file']);
    });

    test('never_ask 下路径工具不询问，直接放行', () async {
      final PermissionRig rig = assemblePermissionRig();

      await rig.tools.call(
        permissionCall('read_file', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(rig.gate.requests, isEmpty);
      expect(rig.runs, <String>['read_file']);
    });

    test('显式 allow 规则跳过路径询问', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(
          askThreshold: ToolRisk.high,
          rules: <PermissionRule>[
            PermissionRule(
              action: 'read',
              resource: '*',
              effect: PermissionEffect.allow,
            ),
          ],
        ),
      );

      await rig.tools.call(
        permissionCall('read_file', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(rig.gate.requests, isEmpty);
      expect(rig.runs, <String>['read_file']);
    });
  });

  group('headless', () {
    test('需要询问时拒绝并返回 PERMISSION_ASK_UNATTENDED', () async {
      final PermissionRig rig = assemblePermissionRig(
        interactive: false,
        attachApproval: false,
        scope: const PermissionScope(askThreshold: ToolRisk.high),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('run_command', <String, Object?>{'command': 'ls'}),
      );
      expect(result.error!.code, 'PERMISSION_ASK_UNATTENDED');
      expect(rig.runs, isEmpty);
    });

    test('零配置下路径工具不触发目录询问（旧行为不拦）', () async {
      final PermissionRig rig = assemblePermissionRig(
        interactive: false,
        attachApproval: false,
        scope: const PermissionScope(askThreshold: ToolRisk.high),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('read_file', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(result.isError, isFalse);
      expect(rig.runs, <String>['read_file']);
    });

    test('显式 allow / never_ask 仍可放行', () async {
      final PermissionRig rig = assemblePermissionRig(
        interactive: false,
        attachApproval: false,
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'shell',
              resource: 'ls *',
              effect: PermissionEffect.allow,
            ),
          ],
        ),
      );

      await rig.tools.call(
        permissionCall('run_command', <String, Object?>{'command': 'ls -la'}),
      );
      expect(rig.runs, <String>['run_command']);
    });
  });
}

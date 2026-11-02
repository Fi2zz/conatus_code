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
              action: 'bash',
              resource: 'git push *',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('bash', <String, Object?>{
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
              action: 'bash',
              resource: 'rm *',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('bash', <String, Object?>{'command': 'rm -rf x'}),
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
        permissionCall('bash', <String, Object?>{'command': 'ls'}),
      );

      expect(result.isError, isFalse);
      expect(rig.gate.requests, hasLength(1));
      expect(rig.gate.requests.single.toolName, 'bash');
      expect(rig.gate.requests.single.action, 'bash');
      expect(rig.runs, <String>['bash']);
    });

    test('拒绝时返回 APPROVAL_DENIED 且不执行', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
        gate: PermissionGateStub(approved: false),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('bash', <String, Object?>{'command': 'ls'}),
      );
      expect(result.error!.code, 'APPROVAL_DENIED');
      expect(rig.runs, isEmpty);
    });

    test('声明路径参数的低风险工具按阈值直接放行（不再为目录信任询问）', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('read', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(result.isError, isFalse);
      expect(rig.gate.requests, isEmpty);
      expect(rig.runs, <String>['read']);
    });

    test('medium 写操作在 askWhenNeeded 下放行，在 alwaysAsk 下询问', () async {
      final PermissionRig relaxed = assemblePermissionRig(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
      );
      await relaxed.tools.call(
        permissionCall('write', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(relaxed.gate.requests, isEmpty);

      final PermissionRig strict = assemblePermissionRig(
        scope: const PermissionScope(askThreshold: ToolRisk.medium),
      );
      await strict.tools.call(
        permissionCall('write', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(strict.gate.requests, hasLength(1));
    });

    test('.env 读默认询问，.env.example 默认放行', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
      );

      await rig.tools.call(
        permissionCall('read', <String, Object?>{'path': '/tmp/.env'}),
      );
      await rig.tools.call(
        permissionCall('read', <String, Object?>{'path': '/tmp/.env.local'}),
      );
      expect(rig.gate.requests, hasLength(2));

      await rig.tools.call(
        permissionCall('read', <String, Object?>{
          'path': '/tmp/.env.example',
        }),
      );
      expect(rig.gate.requests, hasLength(2));
    });

    test('显式 read * allow 覆盖 .env 默认询问', () async {
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
        permissionCall('read', <String, Object?>{'path': '/tmp/.env'}),
      );
      expect(rig.gate.requests, isEmpty);
    });

    test('preapproved 覆盖路径时直接放行，不打扰用户', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
        gate: PermissionGateStub(trusted: true),
      );

      await rig.tools.call(
        permissionCall('read', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(rig.gate.requests, isEmpty);
      expect(rig.runs, <String>['read']);
    });

    test('never_ask 下路径工具不询问，直接放行', () async {
      final PermissionRig rig = assemblePermissionRig();

      await rig.tools.call(
        permissionCall('read', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(rig.gate.requests, isEmpty);
      expect(rig.runs, <String>['read']);
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
        permissionCall('read', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(rig.gate.requests, isEmpty);
      expect(rig.runs, <String>['read']);
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
        permissionCall('bash', <String, Object?>{'command': 'ls'}),
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
        permissionCall('read', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(result.isError, isFalse);
      expect(rig.runs, <String>['read']);
    });

    test('显式 allow / never_ask 仍可放行', () async {
      final PermissionRig rig = assemblePermissionRig(
        interactive: false,
        attachApproval: false,
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'bash',
              resource: 'ls *',
              effect: PermissionEffect.allow,
            ),
          ],
        ),
      );

      await rig.tools.call(
        permissionCall('bash', <String, Object?>{'command': 'ls -la'}),
      );
      expect(rig.runs, <String>['bash']);
    });
  });
}

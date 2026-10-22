/// 工作区外路径的 external_directory 判定。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'permission_rig.dart';

void main() {
  group('external_directory', () {
    test('工作区外 read 进入 external_directory 判定并要求确认', () async {
      final Directory work = Directory.systemTemp.createTempSync('perm-work');
      final Directory outside = Directory.systemTemp.createTempSync(
        'perm-outside',
      );
      addTearDown(() => work.deleteSync(recursive: true));
      addTearDown(() => outside.deleteSync(recursive: true));
      final String file = '${outside.path}${Platform.pathSeparator}a.txt';
      final PermissionRig rig = assemblePermissionRig(
        workdir: work.path,
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'external_directory',
              resource: '*',
              effect: PermissionEffect.ask,
            ),
          ],
        ),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('read_file', <String, Object?>{'path': file}),
      );
      expect(result.isError, isFalse);
      final ApprovalRequest request = rig.gate.requests.single;
      expect(request.action, 'external_directory');
      expect(request.resources.single, endsWith('/*'));
    });

    test('工作区内 read 不触发 external_directory', () async {
      final Directory work = Directory.systemTemp.createTempSync('perm-work');
      addTearDown(() => work.deleteSync(recursive: true));
      final String file = '${work.path}${Platform.pathSeparator}a.txt';
      final PermissionRig rig = assemblePermissionRig(
        workdir: work.path,
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'external_directory',
              resource: '*',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      await rig.tools.call(
        permissionCall('read_file', <String, Object?>{'path': file}),
      );
      expect(rig.runs, <String>['read_file']);
    });

    test('相对路径 ../../ 越界也进入 external_directory', () async {
      final Directory work = Directory.systemTemp.createTempSync('perm-work');
      addTearDown(() => work.deleteSync(recursive: true));
      final PermissionRig rig = assemblePermissionRig(
        workdir: work.path,
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'external_directory',
              resource: '*',
              effect: PermissionEffect.ask,
            ),
          ],
        ),
      );

      await rig.tools.call(
        permissionCall('read_file', <String, Object?>{
          'path': '../../etc/passwd',
        }),
      );
      expect(rig.gate.requests.single.action, 'external_directory');

      await rig.tools.call(
        permissionCall('read_file', <String, Object?>{'path': 'sub/a.txt'}),
      );
      expect(rig.gate.requests, hasLength(1));
    });

    test('统一 diff 的旧路径参与 deny 与 external_directory', () async {
      final Directory work = Directory.systemTemp.createTempSync('perm-work');
      addTearDown(() => work.deleteSync(recursive: true));
      final PermissionRig denyRig = assemblePermissionRig(
        workdir: work.path,
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'edit',
              resource: 'old.txt',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );
      final ToolResult denied = await denyRig.tools.call(
        permissionCall('apply_patch', <String, Object?>{
          'patch': '--- a/old.txt\n+++ b/new.txt\n@@ -1 +1 @@\n-a\n+b',
        }),
      );
      expect(denied.error!.code, 'PERMISSION_DENIED');

      final PermissionRig externalRig = assemblePermissionRig(
        workdir: work.path,
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'external_directory',
              resource: '*',
              effect: PermissionEffect.ask,
            ),
          ],
        ),
      );
      await externalRig.tools.call(
        permissionCall('apply_patch', <String, Object?>{
          'patch':
              '--- a/../outside/old.txt\n+++ b/../outside/new.txt\n'
              '@@ -1 +1 @@\n-a\n+b',
        }),
      );
      expect(externalRig.gate.requests.single.action, 'external_directory');
    });
  });
}

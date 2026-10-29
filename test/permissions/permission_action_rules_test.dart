/// 权限动作映射与按动作编写的规则。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'permission_rig.dart';

void main() {
  group('动作映射', () {
    Future<ApprovalRequest> askFor(
      String tool,
      String action,
      Map<String, Object?> args,
    ) async {
      final PermissionRig rig = assemblePermissionRig(
        scope: PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: action,
              resource: '*',
              effect: PermissionEffect.ask,
            ),
          ],
        ),
      );
      await rig.tools.call(permissionCall(tool, args));
      return rig.gate.requests.single;
    }

    test('run_tests 映射为 shell', () async {
      final ApprovalRequest request = await askFor(
        'run_tests',
        'bash',
        <String, Object?>{'test_cmd': 'dart test'},
      );
      expect(request.action, 'bash');
      expect(request.resources, <String>['dart test']);
    });

    test('websearch 映射为 websearch，资源为查询词', () async {
      final ApprovalRequest request = await askFor(
        'websearch',
        'websearch',
        <String, Object?>{'query': 'dart'},
      );
      expect(request.action, 'websearch');
      expect(request.resources, <String>['dart']);
    });

    test('MCP server__tool 映射为 server_tool', () async {
      final ApprovalRequest request = await askFor(
        'fs__read',
        'fs_read',
        <String, Object?>{},
      );
      expect(request.action, 'fs_read');
      expect(request.resources, <String>['*']);
    });

    test('read / list 映射为 read', () async {
      final ApprovalRequest read = await askFor(
        'read',
        'read',
        <String, Object?>{'path': 'src/a.dart'},
      );
      expect(read.action, 'read');
      expect(read.resources, <String>['src/a.dart']);
      final ApprovalRequest list = await askFor(
        'list',
        'read',
        <String, Object?>{'path': 'src'},
      );
      expect(list.action, 'read');
    });

    test('write / edit / apply_patch 映射为 edit', () async {
      final ApprovalRequest write = await askFor(
        'write',
        'edit',
        <String, Object?>{'path': 'a.txt'},
      );
      expect(write.action, 'edit');
      final ApprovalRequest edit = await askFor(
        'edit',
        'edit',
        <String, Object?>{'path': 'a.txt'},
      );
      expect(edit.action, 'edit');
      final ApprovalRequest patch = await askFor(
        'apply_patch',
        'edit',
        <String, Object?>{'patch': '--- a'},
      );
      expect(patch.action, 'edit');
    });

    test('rg 映射为 grep', () async {
      final ApprovalRequest request = await askFor(
        'grep',
        'grep',
        <String, Object?>{'pattern': 'TODO'},
      );
      expect(request.action, 'grep');
    });

    test('task 映射为 subagent，资源缺省 default', () async {
      final ApprovalRequest request = await askFor(
        'task',
        'task',
        <String, Object?>{'task': '查一下'},
      );
      expect(request.action, 'task');
      expect(request.resources, <String>['default']);
    });

    test('webfetch 映射为 webfetch，资源为 URL', () async {
      final ApprovalRequest request = await askFor(
        'webfetch',
        'webfetch',
        <String, Object?>{'url': 'https://example.com/a'},
      );
      expect(request.action, 'webfetch');
      expect(request.resources, <String>['https://example.com/a']);
    });

    test('question 映射为 question，资源为 *', () async {
      final ApprovalRequest request = await askFor(
        'question',
        'question',
        <String, Object?>{'question': '选哪个'},
      );
      expect(request.action, 'question');
      expect(request.resources, <String>['*']);
    });

    test('grep 资源取 pattern', () async {
      final ApprovalRequest request = await askFor(
        'grep',
        'grep',
        <String, Object?>{'pattern': 'TODO'},
      );
      expect(request.action, 'grep');
      expect(request.resources, <String>['TODO']);
    });
  });

  group('动作规则', () {
    test('action=edit + resource=* 拦截三种写工具', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'edit',
              resource: '*',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      for (final String tool in <String>[
        'write',
        'edit',
        'apply_patch',
      ]) {
        final ToolResult result = await rig.tools.call(
          permissionCall(tool, <String, Object?>{
            'path': 'a.txt',
            'patch': '--- a',
          }),
        );
        expect(result.error!.code, 'PERMISSION_DENIED', reason: tool);
      }
      expect(rig.runs, isEmpty);
    });

    test('action=read 覆盖 read / list', () async {
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
      await rig.tools.call(
        permissionCall('list', <String, Object?>{'path': '/tmp'}),
      );
      expect(rig.gate.requests, isEmpty);
      expect(rig.runs, <String>['read', 'list']);
    });

    test('action=grep 命中 rg，action=shell 命中 bash', () async {
      final PermissionRig grepRig = assemblePermissionRig(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'grep',
              resource: '*',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );
      final ToolResult grep = await grepRig.tools.call(
        permissionCall('grep', <String, Object?>{'pattern': 'TODO'}),
      );
      expect(grep.error!.code, 'PERMISSION_DENIED');

      final PermissionRig shellRig = assemblePermissionRig(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'bash',
              resource: '*',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );
      final ToolResult shell = await shellRig.tools.call(
        permissionCall('bash', <String, Object?>{'command': 'echo hi'}),
      );
      expect(shell.error!.code, 'PERMISSION_DENIED');
    });

    test('action=edit + resource=*.env 只拦截补丁里的 .env 目标', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'edit',
              resource: '*.env',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult blocked = await rig.tools.call(
        permissionCall('apply_patch', <String, Object?>{
          'patch': '*** Update File: config/.env\n@@ -1 +1 @@\n-A=1\n+A=2',
        }),
      );
      expect(blocked.error!.code, 'PERMISSION_DENIED');
      expect(rig.runs, isEmpty);

      final ToolResult allowed = await rig.tools.call(
        permissionCall('apply_patch', <String, Object?>{
          'patch': '*** Update File: src/a.dart\n@@ -1 +1 @@\n-a\n+b',
        }),
      );
      expect(allowed.isError, isFalse);
      expect(rig.runs, <String>['apply_patch']);
    });

    test('apply_patch 解析 Add / Delete / Move to 且去重', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'edit',
              resource: 'secret/*',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult deleted = await rig.tools.call(
        permissionCall('apply_patch', <String, Object?>{
          'patch': '*** Delete File: secret/key.txt',
        }),
      );
      expect(deleted.error!.code, 'PERMISSION_DENIED');

      final ToolResult moved = await rig.tools.call(
        permissionCall('apply_patch', <String, Object?>{
          'patch':
              '*** Update File: src/a.dart\n'
              '*** Move to: secret/b.dart\n',
        }),
      );
      expect(moved.error!.code, 'PERMISSION_DENIED');
    });

    test('action=glob + resource=**/*.dart 命中 glob pattern', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'glob',
              resource: '**/*.dart',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('glob', <String, Object?>{
          'pattern': '**/*.dart',
          'path': 'src',
        }),
      );
      expect(result.error!.code, 'PERMISSION_DENIED');
      expect(rig.runs, isEmpty);
    });

    test('action=skill + resource=review 命中技能名', () async {
      final PermissionRig rig = assemblePermissionRig(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'skill',
              resource: 'review',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult result = await rig.tools.call(
        permissionCall('skill', <String, Object?>{'name': 'review'}),
      );
      expect(result.error!.code, 'PERMISSION_DENIED');
      expect(rig.runs, isEmpty);
    });
  });
}

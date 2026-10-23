/// 权限规则的展示拼写：展开后仍显示用户配置的原始 pattern。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

import 'permission_rig.dart';

void main() {
  test('PermissionRule.displayResource 优先原始配置', () {
    const rule = PermissionRule(
      action: 'edit',
      resource: '/work/src/*',
      configuredResource: 'src/*',
      effect: PermissionEffect.allow,
    );
    expect(rule.displayResource, 'src/*');
    expect(rule.toString(), contains('src/*'));
    expect(rule.toString(), isNot(contains('/work/src/*')));
  });

  test('PermissionWiring 规范化资源时保留原始 pattern', () async {
    final Directory dir = Directory.systemTemp.createTempSync('perm-display');
    addTearDown(() => dir.deleteSync(recursive: true));
    final PermissionWiring wiring = PermissionWiring(
      store: PermissionStore('${dir.path}/permissions.json'),
      workdir: dir.path,
      configRules: const <PermissionRule>[
        PermissionRule(
          action: 'edit',
          resource: 'src/*',
          effect: PermissionEffect.allow,
        ),
      ],
    );
    expect(wiring.configRules.single.resource, '${dir.path}/src/*');
    expect(wiring.configRules.single.displayResource, 'src/*');
  });

  test('审批请求里的命中规则显示原始 pattern', () async {
    final Directory dir = Directory.systemTemp.createTempSync('perm-display');
    addTearDown(() => dir.deleteSync(recursive: true));
    final PermissionRig rig = assemblePermissionRig(
      workdir: dir.path,
      scope: const PermissionScope(
        rules: <PermissionRule>[
          PermissionRule(
            action: 'edit',
            resource: 'src/*',
            effect: PermissionEffect.ask,
          ),
        ],
      ),
    );

    await rig.tools.call(
      permissionCall('write_file', <String, Object?>{
        'path': '${dir.path}/src/a.dart',
      }),
    );
    expect(rig.gate.requests.single.rule, contains('src/*'));
    expect(rig.gate.requests.single.rule, isNot(contains(dir.path)));
  });
}

/// PermissionWiring：规则来源合成与「总是允许」落盘。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('PermissionWiring 持久化', () {
    PermissionWiring wiringFor(
      String dir, {
      List<PermissionRule> configRules = const <PermissionRule>[],
    }) {
      return PermissionWiring(
        store: PermissionStore('$dir${Platform.pathSeparator}permissions.json'),
        configRules: configRules,
      );
    }

    test('remember 写入项目文件并更新作用域（config → project 顺序）', () async {
      final Directory dir = Directory.systemTemp.createTempSync('perm-wiring');
      addTearDown(() => dir.deleteSync(recursive: true));
      const PermissionRule configRule = PermissionRule(
        action: 'shell',
        resource: 'git status *',
        effect: PermissionEffect.allow,
        source: 'config',
      );
      final PermissionWiring wiring = wiringFor(
        dir.path,
        configRules: <PermissionRule>[configRule],
      );
      await wiring.load();
      wiring.applyMode(askThreshold: ToolRisk.high, agentId: 'build');

      final String? warning = await wiring.remember(
        const PermissionRule(
          action: 'shell',
          resource: 'git *',
          effect: PermissionEffect.allow,
          source: 'project',
        ),
      );

      expect(warning, isNull);
      final List<PermissionRule> saved = await PermissionStore(
        '${dir.path}${Platform.pathSeparator}permissions.json',
      ).load();
      expect(saved.single.resource, 'git *');
      expect(
        wiring.slot.current.rules.map((PermissionRule r) => r.resource),
        <String>['git status *', 'git *'],
      );
      expect(wiring.slot.current.askThreshold, ToolRisk.high);
    });

    test('项目文件损坏时返回警告且不改作用域，原文件保留', () async {
      final Directory dir = Directory.systemTemp.createTempSync('perm-wiring');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File file = File(
        '${dir.path}${Platform.pathSeparator}permissions.json',
      )..writeAsStringSync('{broken');
      final PermissionWiring wiring = wiringFor(dir.path);
      await wiring.load();
      wiring.applyMode(askThreshold: ToolRisk.high, agentId: 'build');
      final String before = file.readAsStringSync();

      final String? warning = await wiring.remember(
        const PermissionRule(
          action: 'shell',
          resource: 'git *',
          effect: PermissionEffect.allow,
        ),
      );

      expect(warning, isNotNull);
      expect(warning, contains(file.path));
      expect(wiring.slot.current.rules, isEmpty);
      expect(file.readAsStringSync(), before);
    });
  });
}

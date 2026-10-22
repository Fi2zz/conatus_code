/// PermissionWiring：规则来源合成、「总是允许」落盘与 deny 冲突保护。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
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

    test('remember 写入项目文件并更新作用域（config → project）', () async {
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
        <PermissionRule>[
          const PermissionRule(
            action: 'shell',
            resource: 'git *',
            effect: PermissionEffect.allow,
            source: 'project',
          ),
        ],
        <String>['git status'],
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

    test('已有 deny 匹配被批准资源时拒绝落盘（仅会话放行）', () async {
      final Directory dir = Directory.systemTemp.createTempSync('perm-wiring');
      addTearDown(() => dir.deleteSync(recursive: true));
      const PermissionRule deny = PermissionRule(
        action: 'edit',
        resource: '*.env',
        effect: PermissionEffect.deny,
        source: 'config',
      );
      final PermissionWiring wiring = wiringFor(
        dir.path,
        configRules: <PermissionRule>[deny],
      );
      await wiring.load();
      wiring.applyMode(askThreshold: null, agentId: 'build');

      final String? warning = await wiring.remember(
        <PermissionRule>[
          const PermissionRule(
            action: 'edit',
            resource: 'config/.env',
            effect: PermissionEffect.allow,
          ),
        ],
        <String>['config/.env'],
      );

      expect(warning, isNotNull);
      expect(warning, contains('deny'));
      expect(wiring.slot.current.rules, hasLength(1));
      expect(
        File(
          '${dir.path}${Platform.pathSeparator}permissions.json',
        ).existsSync(),
        isFalse,
      );
    });

    test('shell 前缀 allow 覆盖已有 deny 时拒绝落盘', () async {
      final Directory dir = Directory.systemTemp.createTempSync('perm-wiring');
      addTearDown(() => dir.deleteSync(recursive: true));
      final PermissionWiring wiring = wiringFor(
        dir.path,
        configRules: const <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: 'git push *',
            effect: PermissionEffect.deny,
          ),
        ],
      );
      await wiring.load();

      final String? warning = await wiring.remember(
        const <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: 'git *',
            effect: PermissionEffect.allow,
          ),
        ],
        <String>['git status'],
      );

      expect(warning, isNotNull);
      expect(warning, contains('git push *'));
      expect(
        File(
          '${dir.path}${Platform.pathSeparator}permissions.json',
        ).existsSync(),
        isFalse,
      );
    });

    test('直接传入的 configRules 也会规范化', () async {
      final Directory dir = Directory.systemTemp.createTempSync('perm-wiring');
      addTearDown(() => dir.deleteSync(recursive: true));
      final PermissionWiring wiring = wiringFor(
        dir.path,
        configRules: const <PermissionRule>[
          PermissionRule(
            action: 'edit',
            resource: './src/../src/*.env',
            effect: PermissionEffect.deny,
          ),
        ],
      );
      expect(wiring.configRules.single.resource, 'src/*.env');
    });

    test('会话规则参与合成：config → project → session', () async {
      final Directory dir = Directory.systemTemp.createTempSync('perm-wiring');
      addTearDown(() => dir.deleteSync(recursive: true));
      final PermissionWiring wiring = wiringFor(
        dir.path,
        configRules: const <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: 'a *',
            effect: PermissionEffect.allow,
          ),
        ],
      );
      await wiring.load();
      await wiring.remember(
        const <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: 'b *',
            effect: PermissionEffect.allow,
          ),
        ],
        <String>['b'],
      );
      wiring.setSessionRules(const <PermissionRule>[
        PermissionRule(
          action: 'shell',
          resource: 'c *',
          effect: PermissionEffect.deny,
        ),
      ]);

      expect(
        wiring.slot.current.rules.map((PermissionRule r) => r.resource),
        <String>['a *', 'b *', 'c *'],
      );
    });

    test('路径规则载入 / 落盘时规范化', () async {
      final Directory dir = Directory.systemTemp.createTempSync('perm-wiring');
      addTearDown(() => dir.deleteSync(recursive: true));
      final PermissionWiring wiring = wiringFor(dir.path);
      await wiring.load();
      await wiring.remember(
        const <PermissionRule>[
          PermissionRule(
            action: 'edit',
            resource: './src/../src/a.dart',
            effect: PermissionEffect.allow,
          ),
        ],
        <String>['src/a.dart'],
      );

      expect(wiring.slot.current.rules.single.resource, 'src/a.dart');
      final List<PermissionRule> saved = await PermissionStore(
        '${dir.path}${Platform.pathSeparator}permissions.json',
      ).load();
      expect(saved.single.resource, 'src/a.dart');
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
        const <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: 'git *',
            effect: PermissionEffect.allow,
          ),
        ],
        <String>['git status'],
      );

      expect(warning, isNotNull);
      expect(warning, contains(file.path));
      expect(wiring.slot.current.rules, isEmpty);
      expect(file.readAsStringSync(), before);
    });

    test('更具体的 deny 阻止宽泛 shell allow 落盘', () async {
      final Directory dir = Directory.systemTemp.createTempSync('perm-wiring');
      addTearDown(() => dir.deleteSync(recursive: true));
      final PermissionWiring wiring = wiringFor(
        dir.path,
        configRules: const <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: 'git push origin *',
            effect: PermissionEffect.deny,
            source: 'config',
          ),
        ],
      );
      await wiring.load();

      final String? warning = await wiring.remember(
        const <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: 'git push *',
            effect: PermissionEffect.allow,
            source: 'project',
          ),
        ],
        const <String>['git push --tags'],
      );

      expect(warning, isNotNull);
      expect(warning, contains('git push origin *'));
      expect(
        File(
          '${dir.path}${Platform.pathSeparator}permissions.json',
        ).existsSync(),
        isFalse,
        reason: '拒绝时不能落盘',
      );
    });

    test('配置 workdir 后规则解析为绝对路径', () async {
      final Directory dir = Directory.systemTemp.createTempSync('perm-wiring');
      addTearDown(() => dir.deleteSync(recursive: true));
      final PermissionWiring wiring = PermissionWiring(
        store: PermissionStore(
          '${dir.path}${Platform.pathSeparator}permissions.json',
        ),
        workdir: dir.path,
        configRules: const <PermissionRule>[
          PermissionRule(
            action: 'edit',
            resource: 'src/*',
            effect: PermissionEffect.deny,
          ),
        ],
      );

      expect(
        wiring.configRules.single.resource,
        '${dir.path}${Platform.pathSeparator}src/*'.replaceAll(
          Platform.pathSeparator,
          '/',
        ),
      );
    });

    test('损坏文件记录 loadError，/doctor 给出警告', () async {
      final Directory dir = Directory.systemTemp.createTempSync('perm-wiring');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(
        '${dir.path}${Platform.pathSeparator}permissions.json',
      ).writeAsStringSync('{broken');
      final PermissionWiring wiring = wiringFor(dir.path);
      await wiring.load();

      expect(wiring.loadError, contains('不是合法 JSON'));

      final Context app = Context.root();
      addTearDown(app.dispose);
      app.provide('permissionWiring', wiring);
      final DoctorCheck check = doctorChecks(
        app,
      ).firstWhere((DoctorCheck c) => c.name == '权限规则');
      expect(check.ok, isFalse);
      expect(check.warning, isTrue);
      expect(check.hint, contains('权限文件'));
    });

    test('/doctor 报告被跳过的单条坏规则', () async {
      final Directory dir = Directory.systemTemp.createTempSync('perm-wiring');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(
        '${dir.path}${Platform.pathSeparator}permissions.json',
      ).writeAsStringSync(
        '{"version":1,"rules":['
        '{"action":"shell","resource":"*","effect":"deny"},'
        '{"action":"shell","resource":"*","effect":"bogus"}]}',
      );
      final PermissionWiring wiring = wiringFor(dir.path);
      await wiring.load();

      expect(wiring.loadError, isNull);
      expect(wiring.skippedRules, 1);
      expect(wiring.rules, hasLength(1));

      final Context app = Context.root();
      addTearDown(app.dispose);
      app.provide('permissionWiring', wiring);
      final DoctorCheck check = doctorChecks(
        app,
      ).firstWhere((DoctorCheck c) => c.name == '权限规则');
      expect(check.warning, isTrue);
      expect(check.hint, contains('1 条规则非法'));
    });
  });
}

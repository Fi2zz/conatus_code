/// 命令发现：四层目录优先级、嵌套 ID、无效文件跳过、只读边界。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

import 'command_test_support.dart';

void main() {
  late Directory home;
  late Directory work;

  setUp(() {
    home = Directory.systemTemp.createTempSync('nava-cmd-home');
    work = Directory.systemTemp.createTempSync('nava-cmd-work');
    addTearDown(() {
      home.deleteSync(recursive: true);
      work.deleteSync(recursive: true);
    });
  });

  Future<CommandRegistry> load() =>
      CommandRegistry.load(workdir: work.path, home: home.path);

  test('reload 发现新增 / 删除文件，动态命令保留', () async {
    final Directory root = Directory('${work.path}/.nava/commands');
    final CommandRegistry registry = await load();
    registry.add(const CommandDefinition(
      name: 'dyn',
      template: 'dynamic',
      sourcePath: 'dynamic',
    ));

    writeCommand(root, 'late.md', 'late template');
    await registry.reload();
    expect(registry.byName('late')!.template, 'late template');
    expect(registry.byName('dyn')!.template, 'dynamic');

    File('${root.path}/late.md').deleteSync();
    await registry.reload();
    expect(registry.byName('late'), isNull);
    expect(registry.byName('dyn')!.template, 'dynamic');
  });

  test('优先级：项目 .nava 覆盖全局 .opencode', () async {
    writeCommand(
      Directory('${home.path}/.config/opencode/commands'),
      'review.md',
      'global opencode',
    );
    writeCommand(
      Directory('${home.path}/.nava/commands'),
      'review.md',
      'global nava',
    );
    writeCommand(
      Directory('${work.path}/.opencode/commands'),
      'review.md',
      'project opencode',
    );
    writeCommand(
      Directory('${work.path}/.nava/commands'),
      'review.md',
      'project nava',
    );

    final CommandRegistry registry = await load();

    expect(registry.byName('review')!.sourcePath, contains('.nava'));
    expect(registry.byName('review')!.template, 'project nava');
    expect(registry.all, hasLength(1));
  });

  test('项目 .opencode 覆盖全局 .nava', () async {
    writeCommand(
      Directory('${home.path}/.nava/commands'),
      'review.md',
      'global nava',
    );
    writeCommand(
      Directory('${work.path}/.opencode/commands'),
      'review.md',
      'project opencode',
    );

    final CommandRegistry registry = await load();

    expect(registry.byName('review')!.template, 'project opencode');
  });

  test('全局 .nava 覆盖全局 .opencode', () async {
    writeCommand(
      Directory('${home.path}/.config/opencode/commands'),
      'review.md',
      'global opencode',
    );
    writeCommand(
      Directory('${home.path}/.nava/commands'),
      'review.md',
      'global nava',
    );

    final CommandRegistry registry = await load();

    expect(registry.byName('review')!.template, 'global nava');
  });

  test('嵌套目录形成 team/review ID', () async {
    writeCommand(
      Directory('${work.path}/.nava/commands/team'),
      'review.md',
      'nested',
    );

    final CommandRegistry registry = await load();

    expect(registry.byName('team/review'), isNotNull);
    expect(registry.byName('team/review')!.template, 'nested');
  });

  test('只发现 .md 文件（扩展名大小写不敏感）', () async {
    final Directory root = Directory('${work.path}/.nava/commands');
    writeCommand(root, 'yes.md', 'yes');
    writeCommand(root, 'upper.MD', 'upper');
    writeCommand(root, 'no.txt', 'no');
    writeCommand(root, 'nested/deep.md', 'deep');

    final CommandRegistry registry = await load();

    expect(registry.all.map((CommandDefinition d) => d.name), <String>[
      'nested/deep',
      'upper',
      'yes',
    ]);
  });

  test('无效文件跳过且其余命令照常加载，并记录原因', () async {
    final Directory root = Directory('${work.path}/.nava/commands');
    writeCommand(root, 'good.md', 'good');
    writeCommand(root, 'bad.md', '''
---
agent: 1
---
bad
''');

    final CommandRegistry registry = await load();

    expect(registry.byName('good')!.template, 'good');
    expect(registry.byName('bad'), isNull);
    expect(registry.warnings, hasLength(1));
    expect(registry.warnings.single, contains('bad.md'));
    expect(registry.warnings.single, contains('必须是字符串'));
  });

  test('目录不存在时返回空注册表', () async {
    final CommandRegistry registry = await load();
    expect(registry.all, isEmpty);
    expect(registry.byName('review'), isNull);
  });

  test('add 注册命令并可按名覆盖', () async {
    final CommandRegistry registry = await load();
    const CommandDefinition first = CommandDefinition(
      name: 'x',
      template: 'one',
      sourcePath: '/a.md',
    );
    const CommandDefinition second = CommandDefinition(
      name: 'x',
      template: 'two',
      sourcePath: '/b.md',
    );
    registry.add(first);
    registry.add(second);

    expect(registry.byName('x')!.template, 'two');
    expect(registry.all, hasLength(1));
  });

  test('all 按名称稳定排序', () async {
    final Directory root = Directory('${work.path}/.nava/commands');
    writeCommand(root, 'zeta.md', 'z');
    writeCommand(root, 'alpha.md', 'a');

    final CommandRegistry registry = await load();

    expect(registry.all.map((CommandDefinition d) => d.name), <String>[
      'alpha',
      'zeta',
    ]);
  });

  test('跟随符号链接的命令文件', () async {
    final Directory root = Directory('${work.path}/.nava/commands')
      ..createSync(recursive: true);
    final File target = File('${work.path}/target.md')
      ..writeAsStringSync('linked');
    Link('${root.path}/linked.md').createSync(target.path);

    final CommandRegistry registry = await load();

    expect(registry.byName('linked')!.template, 'linked');
  });

  test('加载不修改 .opencode（文件与内容保持不变）', () async {
    final Directory opencode = Directory('${work.path}/.opencode/commands');
    writeCommand(opencode, 'review.md', 'review body');
    writeCommand(opencode, 'team/deep.md', 'deep body');
    final List<String> before = snapshotDirectory(opencode);

    await load();

    expect(snapshotDirectory(opencode), before);
  });
}

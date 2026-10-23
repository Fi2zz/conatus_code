/// 命令展开：占位符、引号分词、无占位符追加、shell 块与截断。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  Future<String> runNothing(String command) async => '';

  test(r'$ARGUMENTS 替换为完整参数', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: 'Review \$ARGUMENTS.',
      sourcePath: '',
    );

    expect(
      await expandCommand(def, 'a "b c"', runShell: runNothing),
      'Review a "b c".',
    );
  });

  test(r'$1..$9 按引号分词，缺省为空串', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: 'Check \$1 and \$2/\$3',
      sourcePath: '',
    );

    expect(
      await expandCommand(def, '"a b" c', runShell: runNothing),
      'Check a b and c/',
    );
  });

  test('单引号同样分组', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: '\$1|\$2',
      sourcePath: '',
    );

    expect(await expandCommand(def, "'a b' c", runShell: runNothing), 'a b|c');
  });

  test('无占位符时非空参数追加到末尾（空行分隔）', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: 'do it',
      sourcePath: '',
    );

    expect(
      await expandCommand(def, 'extra', runShell: runNothing),
      'do it\n\nextra',
    );
  });

  test('无占位符且参数为空时不追加', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: 'do it',
      sourcePath: '',
    );

    expect(await expandCommand(def, '   ', runShell: runNothing), 'do it');
  });

  test('空模板加参数时直接使用参数', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: '',
      sourcePath: '',
    );

    expect(await expandCommand(def, 'hello', runShell: runNothing), 'hello');
  });

  test('shell 块执行并插入输出', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: 'before\n!`echo hi`\nafter',
      sourcePath: '',
    );
    final List<String> commands = <String>[];

    final String result = await expandCommand(
      def,
      '',
      runShell: (String command) async {
        commands.add(command);
        return 'OUT';
      },
    );

    expect(commands, <String>['echo hi']);
    expect(result, 'before\nOUT\nafter');
  });

  test('多个 shell 块按顺序执行', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: '!`one`!`two`',
      sourcePath: '',
    );
    final List<String> commands = <String>[];

    final String result = await expandCommand(
      def,
      '',
      runShell: (String command) async {
        commands.add(command);
        return '[$command]';
      },
    );

    expect(commands, <String>['one', 'two']);
    expect(result, '[one][two]');
  });

  test('shell 单块输出上限 8000 字符', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: '!`big`',
      sourcePath: '',
    );
    final String big = 'a' * 9000;

    final String result = await expandCommand(
      def,
      '',
      runShell: (String command) async => big,
    );

    expect(result.length, 8000);
    expect(result, 'a' * 8000);
  });

  test('executor 优先于模板展开且接收原始参数', () async {
    final List<String> received = <String>[];
    final CommandDefinition def = CommandDefinition(
      name: 'x',
      template: 'template \$ARGUMENTS',
      sourcePath: '',
      executor: (String args) async {
        received.add(args);
        return 'dynamic';
      },
    );

    final String result = await expandCommand(
      def,
      'raw "args"',
      runShell: (String command) async => fail('不应执行 shell'),
    );

    expect(result, 'dynamic');
    expect(received, <String>['raw "args"']);
  });

  test('shell 失败时抛出，不静默吞掉', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: '!`boom`',
      sourcePath: '',
    );

    await expectLater(
      expandCommand(
        def,
        '',
        runShell: (String command) async =>
            throw const ProcessException('sh', <String>['-c', 'boom']),
      ),
      throwsA(isA<ProcessException>()),
    );
  });

  test('shell 输出中的占位符不会被二次展开', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: '\$ARGUMENTS\n!`emit`',
      sourcePath: '',
    );

    final String result = await expandCommand(
      def,
      'seed',
      runShell: (String command) async => r'$1 literal',
    );

    expect(result, 'seed\n\$1 literal');
  });
}

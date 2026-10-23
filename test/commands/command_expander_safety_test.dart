/// 命令展开的安全边界：参数不能引入可执行 shell 块。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  test('参数中的 shell 块原样保留且不执行', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: 'review \$ARGUMENTS',
      sourcePath: '',
    );
    final List<String> commands = <String>[];

    final String result = await expandCommand(
      def,
      'see !`echo INJECTED` end',
      runShell: (String command) async {
        commands.add(command);
        return 'SHOULD NOT RUN';
      },
    );

    expect(commands, isEmpty);
    expect(result, 'review see !`echo INJECTED` end');
  });

  test('无占位符追加路径也不执行参数里的 shell 块', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: 'review',
      sourcePath: '',
    );
    final List<String> commands = <String>[];

    final String result = await expandCommand(
      def,
      '!`echo INJECTED`',
      runShell: (String command) async {
        commands.add(command);
        return 'SHOULD NOT RUN';
      },
    );

    expect(commands, isEmpty);
    expect(result, 'review\n\n!`echo INJECTED`');
  });

  test('模板内的 shell 块仍按顺序执行', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: 'a !`one` b !`two` c',
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
    expect(result, 'a [one] b [two] c');
  });

  test(r'shell 块内的 $1 不展开为参数', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: '!`echo \$1`',
      sourcePath: '',
    );
    final List<String> commands = <String>[];

    final String result = await expandCommand(
      def,
      'value',
      runShell: (String command) async {
        commands.add(command);
        return 'OUT';
      },
    );

    expect(commands, <String>[r'echo $1']);
    expect(result, 'OUT');
  });

  test('executor 优先于模板与参数中的 shell 块', () async {
    final CommandDefinition def = CommandDefinition(
      name: 'x',
      template: '!`template`',
      sourcePath: '',
      executor: (String args) async => 'dynamic:$args',
    );

    final String result = await expandCommand(
      def,
      '!`arg`',
      runShell: (String command) async => fail('不应执行 shell'),
    );

    expect(result, 'dynamic:!`arg`');
  });

  test('shell 输出按 rune 截断，不切断代理对', () async {
    const CommandDefinition def = CommandDefinition(
      name: 'x',
      template: '!`big`',
      sourcePath: '',
    );

    final String result = await expandCommand(
      def,
      '',
      runShell: (String command) async => '😀' * 9000,
    );

    expect(result.runes.length, kCommandShellOutputLimit);
    expect(result.length, kCommandShellOutputLimit * 2);
    expect(String.fromCharCodes(result.runes), result);
  });
}

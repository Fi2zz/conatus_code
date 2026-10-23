/// 命令分发器：模板展开、shell 错误传播与菜单提示。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

CommandDefinition _def({
  String name = 'draft',
  String template = '处理：\$ARGUMENTS',
  String? agent,
  String? model,
  bool subagent = false,
  String description = '',
}) => CommandDefinition(
  name: name,
  template: template,
  sourcePath: 'test:$name',
  description: description,
  agent: agent,
  model: model,
  subagent: subagent,
);

Future<(CommandDispatcher, Directory)> _dispatcher({
  Map<String, String> commands = const <String, String>{},
  Future<String> Function(String)? runShell,
}) async {
  final Directory root = Directory.systemTemp.createTempSync('nava-dispatch-');
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  for (final MapEntry<String, String> entry in commands.entries) {
    final File file = File('${root.path}/.nava/commands/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  final CommandRegistry registry = await CommandRegistry.load(
    workdir: root.path,
    home: '${root.path}/home',
  );
  final AgentRegistry agents = await AgentRegistry.load(
    workdir: root.path,
    home: '${root.path}/home',
  );
  return (
    CommandDispatcher(
      registry: registry,
      agents: agents,
      providers: null,
      runShell: runShell,
    ),
    root,
  );
}

void main() {
  test('模板展开替换占位符与位置参数', () async {
    final (CommandDispatcher dispatcher, _) = await _dispatcher();
    final String text = await dispatcher.expand(
      _def(template: '全量：\$ARGUMENTS / 首个：\$1'),
      'src/a.dart src/b.dart',
    );
    expect(text, contains('全量：src/a.dart src/b.dart'));
    expect(text, contains('首个：src/a.dart'));
  });

  test('shell 块经 runShell 执行，失败向上抛出', () async {
    final List<String> ran = <String>[];
    final (CommandDispatcher dispatcher, _) = await _dispatcher(
      runShell: (String command) async {
        ran.add(command);
        if (command == 'false') throw StateError('exit 1');
        return 'SHELL-OUT';
      },
    );
    expect(
      await dispatcher.expand(_def(template: '前 !`echo ok` 后'), ''),
      contains('SHELL-OUT'),
    );
    expect(ran, <String>['echo ok']);
    expect(
      () => dispatcher.expand(_def(template: '!`false`'), ''),
      throwsA(isA<StateError>()),
    );
  });

  test('runShell 缺省不可用时抛 StateError', () async {
    final (CommandDispatcher dispatcher, _) = await _dispatcher();
    expect(
      () => dispatcher.expand(_def(template: '!`pwd`'), ''),
      throwsA(isA<StateError>()),
    );
  });

  test('菜单描述带 agent / model / subagent 提示', () async {
    final (CommandDispatcher dispatcher, _) = await _dispatcher();
    final String text = dispatcher.menuDescription(
      _def(description: '起草', agent: 'plan', model: 'beta/b1', subagent: true),
    );
    expect(text, contains('起草'));
    expect(text, contains('agent: plan'));
    expect(text, contains('model: beta/b1'));
    expect(text, contains('前台子 Agent'));
  });

  test('注册表按名查找，未知返回 null', () async {
    final (CommandDispatcher dispatcher, _) = await _dispatcher(
      commands: <String, String>{'draft.md': '---\ndescription: 起草\n---\n正文'},
    );
    expect(dispatcher.byName('draft')?.description, '起草');
    expect(dispatcher.byName('missing'), isNull);
    expect(dispatcher.agentFor(_def(agent: 'plan'))?.id, 'plan');
    expect(dispatcher.agentFor(_def(agent: 'nope')), isNull);
  });
}

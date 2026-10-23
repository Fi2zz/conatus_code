/// MCP prompt → 斜杠命令：命名、位置参数、消息拼接与注册优先级。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import 'support/fake_prompt_server.dart';

Future<McpRegistry> _boot(Context ctx, {bool prompts = true}) => provideMcp(
  ctx,
  <McpServerConfig>[mcpServerConfig('docs')],
  transportFactory: (_) => fakePromptServer('docs', prompts: prompts),
);

Future<List<CommandDefinition>> _commands({bool prompts = true}) async {
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  provideTools(ctx);
  return loadMcpPromptCommands(await _boot(ctx, prompts: prompts));
}

void main() {
  test('prompt 命令命名为 <server>:<prompt>', () async {
    final List<CommandDefinition> commands = await _commands();
    expect(commands.single.name, 'docs:review');
    expect(commands.single.description, '审查代码');
    expect(commands.single.sourcePath, '');
    expect(commands.single.executor, isNotNull);
  });

  test('执行体按位置填参并拼成 role: text 段落', () async {
    final List<CommandDefinition> commands = await _commands();
    final String output = await commands.single.executor!('"a b.dart" 2');
    expect(output, 'user: path=a b.dart;depth=2\n\nassistant: 看到 a b.dart');
  });

  test('必填参数缺省补空串，可选参数缺省直接省略', () async {
    final List<CommandDefinition> commands = await _commands();
    final String output = await commands.single.executor!('');
    expect(output, contains('path=;depth=<absent>'));
  });

  test('显式空串与「没传」可区分', () async {
    final List<CommandDefinition> commands = await _commands();
    final String output = await commands.single.executor!('p ""');
    expect(output, contains('path=p;depth='));
    expect(output, isNot(contains('<absent>')));
  });

  test('未声明 prompts 能力：无命令，也不发 prompts/list', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    provideTools(ctx);
    final List<String> methods = <String>[];
    final McpRegistry registry = await provideMcp(
      ctx,
      <McpServerConfig>[mcpServerConfig('docs')],
      transportFactory: (_) =>
          fakePromptServer('docs', prompts: false, log: methods),
    );
    final List<CommandDefinition> commands = await loadMcpPromptCommands(
      registry,
    );
    expect(commands, isEmpty);
    expect(methods, isNot(contains('prompts/list')));
  });

  test('名为 skill 的 server 跳过并告警', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    provideTools(ctx);
    final McpRegistry registry = await provideMcp(ctx, <McpServerConfig>[
      mcpServerConfig('skill'),
    ], transportFactory: (_) => fakePromptServer('skill'));
    final List<String> warnings = <String>[];
    final List<CommandDefinition> commands = await loadMcpPromptCommands(
      registry,
      onWarning: warnings.add,
    );
    expect(commands, isEmpty);
    expect(warnings.single, contains('skill'));
  });

  test('注册时同名磁盘命令优先', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-cmd');
    addTearDown(() => dir.deleteSync(recursive: true));
    final CommandRegistry registry = await CommandRegistry.load(
      workdir: dir.path,
      home: dir.path,
    );
    registry.add(
      const CommandDefinition(
        name: 'docs:review',
        template: '磁盘命令',
        sourcePath: '/tmp/disk.md',
      ),
    );
    final int added = registerMcpPromptCommands(registry, await _commands());
    expect(added, 0);
    final CommandDefinition? def = registry.byName('docs:review');
    expect(def?.template, '磁盘命令');
    expect(def?.executor, isNull);
  });
}

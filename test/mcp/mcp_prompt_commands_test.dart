/// MCP prompt → 斜杠命令：命名、位置参数与消息拼接。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import 'support/fake_prompt_server.dart';

Future<McpRegistry> _boot(Context ctx, {bool prompts = true}) => provideMcp(
  ctx,
  <McpServerConfig>[docsServerConfig()],
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

  test('缺省参数填空串', () async {
    final List<CommandDefinition> commands = await _commands();
    final String output = await commands.single.executor!('only');
    expect(output, contains('path=only;depth='));
  });

  test('未声明 prompts 能力：无命令，也不发 prompts/list', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    provideTools(ctx);
    final List<String> methods = <String>[];
    final McpRegistry registry = await provideMcp(
      ctx,
      <McpServerConfig>[docsServerConfig()],
      transportFactory: (_) =>
          fakePromptServer('docs', prompts: false, log: methods),
    );
    final List<CommandDefinition> commands = await loadMcpPromptCommands(
      registry,
    );
    expect(commands, isEmpty);
    expect(methods, isNot(contains('prompts/list')));
  });
}

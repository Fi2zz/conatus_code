/// MCP prompt 命令的按需加载：装配期不联网，首次用到时再拉。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import 'support/fake_prompt_server.dart';

Future<(McpPromptCommands, CommandRegistry, List<String>)> _boot() async {
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  provideTools(ctx);
  final List<String> methods = <String>[];
  final McpRegistry mcp = await provideMcp(
    ctx,
    <McpServerConfig>[mcpServerConfig('docs')],
    transportFactory: (_) => fakePromptServer('docs', log: methods),
  );
  final Directory dir = Directory.systemTemp.createTempSync('nava-prompt');
  addTearDown(() => dir.deleteSync(recursive: true));
  final CommandRegistry commands = await CommandRegistry.load(
    workdir: dir.path,
    home: dir.path,
  );
  return (
    McpPromptCommands(registry: mcp, commands: commands, warn: (_) {}),
    commands,
    methods,
  );
}

void main() {
  test('装配期不拉取：没有 prompts/list，也没有 prompt 命令', () async {
    final (McpPromptCommands service, CommandRegistry commands, List<String> methods) =
        await _boot();

    expect(service.loaded, isFalse);
    expect(methods, isNot(contains('prompts/list')));
    expect(commands.byName('docs:review'), isNull);
  });

  test('ensureLoaded：拉取一次并登记 <server>:<prompt> 命令', () async {
    final (McpPromptCommands service, CommandRegistry commands, List<String> methods) =
        await _boot();

    await service.ensureLoaded();

    expect(service.loaded, isTrue);
    expect(methods.where((String m) => m == 'prompts/list'), hasLength(1));
    expect(commands.byName('docs:review'), isNotNull);
  });

  test('ensureLoaded 幂等：并发与重复调用只发一次 prompts/list', () async {
    final (McpPromptCommands service, CommandRegistry commands, List<String> methods) =
        await _boot();

    await Future.wait(<Future<void>>[service.ensureLoaded(), service.ensureLoaded()]);
    await service.ensureLoaded();

    expect(methods.where((String m) => m == 'prompts/list'), hasLength(1));
    expect(commands.all.where((CommandDefinition c) => c.name == 'docs:review'),
        hasLength(1));
  });
}

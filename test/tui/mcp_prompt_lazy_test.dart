/// MCP prompt 命令按需加载：装配期不拉，打开/使用命令时才拉一次。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

import '../mcp/support/fake_prompt_server.dart';

Future<(ConatusTuiRuntime, List<String>)> _create() async {
  final Directory dir = Directory.systemTemp.createTempSync('nava-lazy-prompt');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String sep = Platform.pathSeparator;
  final List<String> methods = <String>[];
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    baseDir: dir.path,
    sessionDir: dir.path,
    memoryFile: '${dir.path}${sep}memory.json',
    webTools: false,
    skills: false,
    llm: FallbackLlm(const <LlmProvider>[]),
    workdir: dir.path,
    mcpServers: const <McpServerSpec>[
      McpServerSpec(name: 'docs', type: McpServerType.stdio, command: 'x'),
    ],
    mcpTransportFactory: (_) => fakePromptServer('docs', log: methods),
  );
  addTearDown(runtime.dispose);
  return (runtime, methods);
}

void main() {
  test('装配期不请求 prompts/list，服务处于未加载态', () async {
    final (ConatusTuiRuntime runtime, List<String> methods) = await _create();

    expect(methods, isNot(contains('prompts/list')));
    expect(
      runtime.app.get<McpPromptCommands>('mcpPromptCommands')?.loaded,
      isFalse,
    );
  });

  test('ensurePromptCommands：首次加载并登记命令，之后不再重复请求', () async {
    final (ConatusTuiRuntime runtime, List<String> methods) = await _create();
    final ConatusTuiController controller = runtime.createController(
      onExit: () {},
    );
    expect(
      controller.commands.map((TuiCommand c) => c.name),
      isNot(contains('docs:review')),
    );

    expect(await controller.ensurePromptCommands(), isTrue);

    expect(
      controller.commands.map((TuiCommand c) => c.name),
      contains('docs:review'),
    );
    expect(methods.where((String m) => m == 'prompts/list'), hasLength(1));

    expect(await controller.ensurePromptCommands(), isFalse);
    expect(methods.where((String m) => m == 'prompts/list'), hasLength(1));
  });

  test('/help 首次调用就带上 prompt 命令（按需加载）', () async {
    final (ConatusTuiRuntime runtime, List<String> methods) = await _create();
    final ConatusTuiController controller = runtime.createController(
      onExit: () {},
    );

    await controller.handleLine('/help');

    expect(controller.transcript.messages.last.text, contains('/docs:review'));
    expect(methods.where((String m) => m == 'prompts/list'), hasLength(1));
  });

  test('敲了未知命令也会补拉一次，之后命令表里可见', () async {
    final (ConatusTuiRuntime runtime, List<String> methods) = await _create();
    final ConatusTuiController controller = runtime.createController(
      onExit: () {},
    );

    await controller.handleLine('/nope');

    expect(controller.transcript.messages.last.text, contains('未知命令：/nope'));
    expect(
      controller.commands.map((TuiCommand c) => c.name),
      contains('docs:review'),
    );
    expect(methods.where((String m) => m == 'prompts/list'), hasLength(1));
  });
}

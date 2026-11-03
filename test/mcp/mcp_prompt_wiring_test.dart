/// tui_app 装配：资源工具与 prompt 命令进注册表。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

import 'support/fake_prompt_server.dart';

class _Stub implements LlmProvider {
  @override
  String get name => 'stub';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async => const LlmResult(content: 'ok', provider: 'stub', model: 'stub');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

Future<ConatusTuiRuntime> _bootRuntime(Directory dir) async {
  final Directory home = Directory('${dir.path}/home')..createSync();
  final ConatusTuiRuntime rt = await ConatusTuiRuntime.create(
    baseDir: dir.path,
    sessionDir: dir.path,
    memoryFile: '${dir.path}/memory.json',
    workdir: dir.path,
    webTools: false,
    skills: false,
    commandHome: home.path,
    llm: FallbackLlm(<LlmProvider>[_Stub()]),
    mcpServers: <McpServerSpec>[
      const McpServerSpec(
        name: 'docs',
        type: McpServerType.stdio,
        command: 'x',
      ),
    ],
    mcpTransportFactory: (_) => fakePromptServer('docs'),
  );
  addTearDown(rt.dispose);
  return rt;
}

void main() {
  test('tui_app 装配：资源工具就绪；prompt 命令按需加载', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-prompt');
    addTearDown(() => dir.deleteSync(recursive: true));
    final ConatusTuiRuntime rt = await _bootRuntime(dir);

    expect(rt.app.tools.get('list_mcp_resources'), isNotNull);
    expect(rt.app.tools.get('read_mcp_resource'), isNotNull);
    final CommandRegistry registry = rt.app.require<CommandRegistry>(
      'commandRegistry',
    );
    // 装配期不联网拉 prompts 目录（见 McpPromptCommands）。
    expect(registry.byName('docs:review'), isNull);

    await rt.app.require<McpPromptCommands>('mcpPromptCommands').ensureLoaded();
    final CommandDefinition? def = registry.byName('docs:review');
    expect(def, isNotNull, reason: '按需加载后 prompt 命令应进注册表');
    expect(def!.executor, isNotNull);
  });
}

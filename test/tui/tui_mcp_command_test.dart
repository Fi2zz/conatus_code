/// `/mcp` 命令：列出已接入的 MCP server（就绪状态 / 工具数）。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

import '../mcp/support/fake_mcp_transport.dart';

/// 占位 LLM：`/mcp` 不触发模型调用，只要求 `'llm'` 服务存在。
class _StubProvider implements LlmProvider {
  @override
  String get name => 'stub';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      Future<LlmResult>.error(StateError('stub 不应被调用'));

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 装配一个带两台假 MCP server 的控制器（复用 mcp_assembly 的挂载路径）。
Future<(ConatusTuiController, Context)> _buildWithMcp() async {
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
  final SessionStore sessions = provideSessions(app);
  final FakeMcpServers fakes = FakeMcpServers();
  await attachMcpServers(
    app,
    const <McpServerSpec>[
      McpServerSpec(name: 'fs', type: McpServerType.stdio, command: 'npx'),
      McpServerSpec(name: 'net', type: McpServerType.http, url: 'https://x'),
    ],
    transportFactory: fakes.build,
  );
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    onExit: () {},
  );
  await controller.start();
  return (controller, app);
}

void main() {
  test('有 server 时列出名称、就绪状态与工具数', () async {
    final (ConatusTuiController controller, Context app) =
        await _buildWithMcp();
    addTearDown(app.dispose);

    await controller.handleLine('/mcp');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('已接入 MCP server（2）：'));
    expect(text, contains('fs［就绪］工具 1 个'));
    expect(text, contains('net［就绪］工具 1 个'));
  });

  test('未配置 server 时提示配置入口', () async {
    final Context app = Context.root();
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
    final SessionStore sessions = provideSessions(app);
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: 'test',
      modelLabel: 'mock',
      onExit: () {},
    );
    addTearDown(app.dispose);
    await controller.start();

    await controller.handleLine('/mcp');

    expect(
      controller.transcript.messages.last.text,
      contains('未配置 MCP server（config.toml [mcp.servers.*]）'),
    );
  });

  test('命令表包含 mcp 且帮助里可查', () {
    final TuiCommand mcp =
        tuiCommands.firstWhere((TuiCommand c) => c.name == 'mcp');
    expect(mcp.description, contains('MCP server'));
    expect(mcp.takesArgs, isFalse);
  });
}

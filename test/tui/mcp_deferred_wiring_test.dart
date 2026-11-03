/// MCP 后台连接：首帧不等握手，首轮请求前补齐工具。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import '../mcp/support/fake_mcp_transport.dart';
import '../mcp/support/fake_prompt_server.dart';

class _CaptureProvider implements LlmProvider {
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];

  @override
  String get name => 'capture';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(messages);
    return const LlmResult(content: '好的', provider: 'capture', model: 'm');
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 造一台握手卡在 [gate] 上的假 MCP server。
FakeMcpTransport _gatedServer(Completer<void> gate) {
  final FakeMcpTransport transport = fakePromptServer('docs');
  final Future<void> Function(McpMessage) reply = transport.onSend!;
  transport.onSend = (McpMessage message) async {
    if (message.method == 'initialize') await gate.future;
    await reply(message);
  };
  return transport;
}

Future<(ConatusTuiRuntime, _CaptureProvider, Completer<void>)> _create({
  bool defer = true,
}) async {
  final Directory dir = Directory.systemTemp.createTempSync('nava-mcp-defer');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String sep = Platform.pathSeparator;
  final Completer<void> gate = Completer<void>();
  final _CaptureProvider provider = _CaptureProvider();
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    baseDir: dir.path,
    sessionDir: dir.path,
    memoryFile: '${dir.path}${sep}memory.json',
    webTools: false,
    skills: false,
    llm: FallbackLlm(<LlmProvider>[provider]),
    workdir: dir.path,
    mcpServers: const <McpServerSpec>[
      McpServerSpec(name: 'docs', type: McpServerType.stdio, command: 'x'),
    ],
    // 同步装配用例不注入门闩，否则 create 会一直等握手。
    mcpTransportFactory: (_) => defer ? _gatedServer(gate) : fakePromptServer('docs'),
    deferMcpConnect: defer,
  );
  addTearDown(runtime.dispose);
  return (runtime, provider, gate);
}

void main() {
  test('defer：create 先返回，握手完成前没有 MCP 工具', () async {
    final (ConatusTuiRuntime runtime, _, Completer<void> gate) = await _create();

    expect(runtime.mcpReady, isNotNull);
    expect(runtime.mcpBoot?.done, isFalse);
    expect(runtime.tools.get('list_mcp_resources'), isNull);
    expect(runtime.app.get<McpPromptCommands>('mcpPromptCommands'), isNull);

    gate.complete();
    await runtime.mcpReady;

    expect(runtime.mcpBoot?.done, isTrue);
    expect(runtime.tools.get('list_mcp_resources'), isNotNull);
    expect(runtime.app.get<McpPromptCommands>('mcpPromptCommands'), isNotNull);
  });

  test('defer=false：create 返回时工具已就绪（headless 语义不变）', () async {
    final (ConatusTuiRuntime runtime, _, _) = await _create(defer: false);

    expect(runtime.mcpBoot, isNull);
    expect(runtime.tools.get('list_mcp_resources'), isNotNull);
  });

  test('首轮请求等 MCP 就绪后才调用模型', () async {
    final (ConatusTuiRuntime runtime, _CaptureProvider provider, Completer<void> gate) =
        await _create();
    final ConatusTuiController controller = runtime.createController(
      onExit: () {},
    );
    await controller.start();

    final Future<void> turn = controller.submit('你好');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(provider.calls, isEmpty, reason: 'MCP 未就绪时不该先发请求');

    gate.complete();
    await turn;
    expect(provider.calls, isNotEmpty);
  });

  test('握手期 /mcp 与 /doctor 都显示连接中', () async {
    final (ConatusTuiRuntime runtime, _, Completer<void> gate) = await _create();
    final ConatusTuiController controller = runtime.createController(
      onExit: () {},
    );

    await controller.handleLine('/mcp');
    expect(controller.transcript.messages.last.text, contains('连接中'));

    await controller.handleLine('/doctor');
    expect(controller.transcript.messages.last.text, contains('MCP server'));
    expect(controller.transcript.messages.last.text, contains('连接中'));

    gate.complete();
    await runtime.mcpReady;
  });

  test('连接进行中释放运行时：取消后续接线并正常返回', () async {
    final (ConatusTuiRuntime runtime, _, Completer<void> gate) = await _create();
    final McpBoot boot = runtime.mcpBoot!;

    final Future<void> disposing = runtime.dispose();
    expect(boot.cancelled, isTrue);

    gate.complete();
    await disposing;
  });
}

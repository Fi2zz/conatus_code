/// MCP 装配：逐台挂载、失败跳过、占位符解析、默认传输分派。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import 'support/fake_mcp_transport.dart';

void main() {
  late Context ctx;
  late ToolRegistry tools;
  late FakeMcpServers fakes;

  setUp(() {
    ctx = Context.root();
    tools = provideTools(ctx);
    fakes = FakeMcpServers();
  });

  tearDown(() {
    if (!ctx.disposed) ctx.dispose();
  });

  const List<McpServerSpec> twoSpecs = <McpServerSpec>[
    McpServerSpec(
      name: 'fs',
      type: McpServerType.stdio,
      command: 'npx',
      env: <String, String>{'API_KEY': r'${TAVILY_API_KEY}'},
    ),
    McpServerSpec(
      name: 'net',
      type: McpServerType.http,
      url: 'https://example.com/mcp',
      headers: <String, String>{'Authorization': r'Bearer ${MISSING_KEY}'},
    ),
  ];

  test('空列表返回 null，不占 mcp 服务键', () async {
    expect(await attachMcpServers(ctx, const <McpServerSpec>[]), isNull);
    expect(ctx.get<McpRegistry>('mcp'), isNull);
  });

  test('两台 server 全部挂载：工具进 ctx.tools，client 就绪', () async {
    final McpRegistry? registry = await attachMcpServers(
      ctx,
      twoSpecs,
      transportFactory: fakes.build,
    );

    expect(registry, isNotNull);
    expect(registry!.servers, <String>['fs', 'net']);
    expect(ctx.mcp.servers, <String>['fs', 'net']);
    expect(registry.clientOf('fs')?.ready, isTrue);
    expect(registry.toolsOf('fs').single.name, 'fs__read_file');
    expect(tools.names, containsAll(<String>['fs__read_file', 'net__read_file']));
  });

  test('单台连接失败 → 提示并跳过，其余照常挂载', () async {
    final List<String> messages = <String>[];
    final McpRegistry registry = (await attachMcpServers(
      ctx,
      <McpServerSpec>[
        const McpServerSpec(name: 'broken', type: McpServerType.stdio, command: 'x'),
        const McpServerSpec(name: 'ok', type: McpServerType.stdio, command: 'npx'),
      ],
      transportFactory: (McpServerConfig config) {
        final FakeMcpTransport transport =
            config.name == 'broken' ? FakeMcpTransport() : fakes.build(config);
        if (config.name == 'broken') {
          transport.connectError = StateError('npx 不在 PATH');
        }
        return transport;
      },
      onError: messages.add,
    ))!;

    expect(messages, hasLength(1));
    expect(messages.single, contains('broken'));
    expect(messages.single, contains('已跳过'));
    expect(registry.servers, <String>['ok']);
    expect(tools.names, contains('ok__read_file'));
    expect(tools.names, isNot(contains('broken__read_file')));
  });

  test('env/headers 占位符经凭据解析；缺失键原样保留', () async {
    final Credentials credentials = InMemoryCredentials(
      initial: <String, String>{'TAVILY_API_KEY': 'tvly-secret'},
    );

    await attachMcpServers(
      ctx,
      twoSpecs,
      credentials: credentials,
      transportFactory: fakes.build,
    );

    expect(fakes.configs['fs']?.env, <String, String>{'API_KEY': 'tvly-secret'});
    expect(
      fakes.configs['net']?.headers,
      <String, String>{'Authorization': r'Bearer ${MISSING_KEY}'},
    );
  });

  test('toMcpTransport 按类型分派默认实现', () {
    expect(
      toMcpTransport(McpServerConfig(
        name: 's',
        type: McpTransportType.stdio,
        command: 'npx',
      )),
      isA<StdioTransport>(),
    );
    expect(
      toMcpTransport(McpServerConfig(
        name: 'h',
        type: McpTransportType.http,
        url: 'https://x',
      )),
      isA<HttpTransport>(),
    );
    expect(
      toMcpTransport(McpServerConfig(
        name: 'e',
        type: McpTransportType.sse,
        url: 'https://x',
      )),
      isA<SseTransport>(),
    );
  });
}

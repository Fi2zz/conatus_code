/// MCP 装配：逐台挂载、失败跳过、占位符解析、默认传输分派。
library;

import 'package:conatus_agent/conatus_agent.dart'
    show AutoApproval, provideApproval;
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
    expect(registry.toolsOf('fs').single.name, 'fs__read');
    expect(
      tools.names,
      containsAll(<String>['fs__read', 'net__read']),
    );
  });

  test('单台连接失败 → 提示并跳过，其余照常挂载', () async {
    final List<String> messages = <String>[];
    final McpRegistry registry = (await attachMcpServers(
      ctx,
      <McpServerSpec>[
        const McpServerSpec(
          name: 'broken',
          type: McpServerType.stdio,
          command: 'x',
        ),
        const McpServerSpec(
          name: 'ok',
          type: McpServerType.stdio,
          command: 'npx',
        ),
      ],
      transportFactory: (McpServerConfig config) {
        final FakeMcpTransport transport = config.name == 'broken'
            ? FakeMcpTransport()
            : fakes.build(config);
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
    expect(tools.names, contains('ok__read'));
    expect(tools.names, isNot(contains('broken__read')));
  });

  test('传输构造抛错不中断整循环：报告并跳过，其余照常挂载', () async {
    final List<String> messages = <String>[];
    final McpRegistry registry = (await attachMcpServers(
      ctx,
      <McpServerSpec>[
        const McpServerSpec(
          name: 'bad',
          type: McpServerType.stdio,
          command: 'x',
        ),
        const McpServerSpec(
          name: 'ok',
          type: McpServerType.stdio,
          command: 'npx',
        ),
      ],
      transportFactory: (McpServerConfig config) {
        if (config.name == 'bad') throw StateError('构造传输即炸');
        return fakes.build(config);
      },
      onError: messages.add,
    ))!;

    expect(messages, hasLength(1));
    expect(messages.single, contains('bad'));
    expect(registry.servers, <String>['ok']);
    expect(tools.names, contains('ok__read'));
  });

  test('未解析的占位符报告键名（不泄露值）', () async {
    final List<String> messages = <String>[];
    await attachMcpServers(
      ctx,
      <McpServerSpec>[
        const McpServerSpec(
          name: 'net',
          type: McpServerType.http,
          url: 'https://x',
          headers: <String, String>{'Authorization': r'Bearer ${MISSING_KEY}'},
        ),
      ],
      transportFactory: fakes.build,
      onError: messages.add,
    );

    expect(messages, hasLength(1));
    expect(messages.single, contains('MISSING_KEY'));
    expect(messages.single, contains('headers'));
    expect(messages.single, isNot(contains('Bearer')));
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

    expect(fakes.configs['fs']?.env, <String, String>{
      'API_KEY': 'tvly-secret',
    });
    expect(fakes.configs['net']?.headers, <String, String>{
      'Authorization': r'Bearer ${MISSING_KEY}',
    });
  });

  // E-10 回归：假 server 未声明任何风险信号，工具须提级 high——缺省审批阈值
  // （provideApproval threshold=high）才拦得住；medium 会静默放行，而 MCP
  // stdio 子进程不经本地沙箱，审批是唯一防线。
  test('未声明风险的 MCP 工具在缺省阈值下被审批拦截', () async {
    final McpRegistry? registry = await attachMcpServers(ctx, <McpServerSpec>[
      const McpServerSpec(
        name: 'fs',
        type: McpServerType.stdio,
        command: 'npx',
      ),
    ], transportFactory: fakes.build);

    expect(registry!.toolsOf('fs').single.riskLevel, ToolRisk.high);
    provideApproval(ctx, approval: AutoApproval(false));
    final ToolResult result = await ctx.tools.call(
      const ToolCall(name: 'fs__read'),
    );

    expect(result.isError, isTrue);
    expect(result.error!.code, 'APPROVAL_DENIED');
  });

  test('toMcpTransport 按类型分派默认实现', () {
    expect(
      toMcpTransport(
        McpServerConfig(
          name: 's',
          type: McpTransportType.stdio,
          command: 'npx',
        ),
      ),
      isA<StdioTransport>(),
    );
    expect(
      toMcpTransport(
        McpServerConfig(
          name: 'h',
          type: McpTransportType.http,
          url: 'https://x',
        ),
      ),
      isA<HttpTransport>(),
    );
    expect(
      toMcpTransport(
        McpServerConfig(
          name: 'e',
          type: McpTransportType.sse,
          url: 'https://x',
        ),
      ),
      isA<SseTransport>(),
    );
  });
}

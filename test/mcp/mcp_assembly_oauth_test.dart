/// MCP 装配的 OAuth 运行时行为：无令牌只跳过该 server，有令牌正常挂载。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import 'support/fake_mcp_transport.dart';

void main() {
  late Context ctx;
  late FakeMcpServers fakes;
  late Directory dir;

  setUp(() {
    ctx = Context.root();
    provideTools(ctx);
    fakes = FakeMcpServers();
    dir = Directory.systemTemp.createTempSync('mcp-assembly-oauth-');
  });

  tearDown(() {
    if (!ctx.disposed) ctx.dispose();
    dir.deleteSync(recursive: true);
  });

  const McpServerSpec remote = McpServerSpec(
    name: 'net',
    type: McpServerType.http,
    url: 'https://example.com/mcp',
  );

  const McpServerSpec local = McpServerSpec(
    name: 'fs',
    type: McpServerType.stdio,
    command: 'npx',
  );

  test('无令牌：该 server 标记 needs_auth 并跳过，其余照常挂载', () async {
    final List<String> messages = <String>[];
    final McpRegistry registry = (await attachMcpServers(
      ctx,
      <McpServerSpec>[local, remote],
      transportFactory: fakes.build,
      oauthStore: McpOAuthStore(dir.path),
      onError: messages.add,
    ))!;

    expect(registry.servers, <String>['fs']);
    expect(fakes.transports.keys, <String>['fs']);
    expect(messages, hasLength(1));
    expect(messages.single, contains('net'));
    expect(messages.single, contains('needs_auth'));
    expect(messages.single, contains('mcp auth net'));
    expect(dir.listSync(), isEmpty);
  });

  test('有令牌：正常挂载，且令牌不进配置头', () async {
    final McpOAuthStore store = McpOAuthStore(dir.path);
    await store.save('net', const McpOAuthToken(accessToken: 'access-secret'));
    final List<String> messages = <String>[];

    final McpRegistry registry = (await attachMcpServers(
      ctx,
      <McpServerSpec>[local, remote],
      transportFactory: fakes.build,
      oauthStore: store,
      onError: messages.add,
    ))!;

    expect(registry.servers, <String>['fs', 'net']);
    expect(messages, isEmpty);
    expect(fakes.configs['net']!.headers, isEmpty);
    expect((await store.load('net'))!.accessToken, 'access-secret');
  });

  test('oauth = false：没有令牌也照常挂载', () async {
    final List<String> messages = <String>[];

    final McpRegistry registry = (await attachMcpServers(
      ctx,
      <McpServerSpec>[
        const McpServerSpec(
          name: 'net',
          type: McpServerType.http,
          url: 'https://example.com/mcp',
          oauth: McpOAuthConfig(enabled: false),
        ),
      ],
      transportFactory: fakes.build,
      oauthStore: McpOAuthStore(dir.path),
      onError: messages.add,
    ))!;

    expect(registry.servers, <String>['net']);
    expect(messages, isEmpty);
  });

  test('缺令牌的 server 不影响其余远程 server', () async {
    await McpOAuthStore(
      dir.path,
    ).save('oknet', const McpOAuthToken(accessToken: 't'));
    final List<String> messages = <String>[];

    final McpRegistry registry = (await attachMcpServers(
      ctx,
      <McpServerSpec>[
        remote,
        const McpServerSpec(
          name: 'oknet',
          type: McpServerType.sse,
          url: 'https://example.com/sse',
        ),
      ],
      transportFactory: fakes.build,
      oauthStore: McpOAuthStore(dir.path),
      onError: messages.add,
    ))!;

    expect(registry.servers, <String>['oknet']);
    expect(messages.single, contains('net'));
  });
}

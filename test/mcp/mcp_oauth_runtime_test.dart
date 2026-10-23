/// 装配期 OAuth 运行时：Bearer 头、主动刷新、401 刷新、失败收敛与单飞。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/fake_oauth_server.dart';

void main() {
  late FakeOAuthServer authServer;
  late Directory dir;
  late McpOAuthStore store;
  late McpServerSpec spec;

  setUp(() async {
    authServer = await FakeOAuthServer.start();
    dir = Directory.systemTemp.createTempSync('mcp-oauth-runtime-');
    store = McpOAuthStore(dir.path);
    spec = McpServerSpec(
      name: 'docs',
      type: McpServerType.http,
      url: '${authServer.issuer}/mcp',
    );
  });

  tearDown(() async {
    await authServer.close();
    dir.deleteSync(recursive: true);
  });

  McpOAuthToken token({
    String access = 'access-1',
    String? refresh = 'refresh-1',
    DateTime? expiresAt,
  }) => McpOAuthToken(
    accessToken: access,
    refreshToken: refresh,
    expiresAt: expiresAt,
  ).withClient(clientId: 'dcr-client-1');

  Future<McpOAuthRuntime> runtimeFor(McpOAuthToken initial) async {
    await store.save(spec.name, initial);
    return McpOAuthRuntime(spec: spec, store: store, initial: initial);
  }

  test('有效令牌直接给 Bearer 头，不读文件也不刷新', () async {
    final McpOAuthRuntime runtime = await runtimeFor(
      token(expiresAt: DateTime.now().add(const Duration(hours: 1))),
    );

    expect(await runtime.headers(), <String, String>{
      'Authorization': 'Bearer access-1',
    });
    expect(await runtime.headers(), <String, String>{
      'Authorization': 'Bearer access-1',
    });
    expect(authServer.tokenRequests, isEmpty);
  });

  test('临过期主动刷新一次并落盘', () async {
    final McpOAuthRuntime runtime = await runtimeFor(
      token(expiresAt: DateTime.now().add(const Duration(seconds: 10))),
    );

    final Map<String, String> headers = await runtime.headers();

    expect(headers['Authorization'], 'Bearer access-2');
    expect((await store.load('docs'))!.accessToken, 'access-2');
    expect(authServer.tokenRequests, hasLength(1));
    expect(authServer.tokenRequests.single['grant_type'], 'refresh_token');
    expect(authServer.tokenRequests.single['client_id'], 'dcr-client-1');
    expect(authServer.tokenRequests.single['resource'], spec.url);
  });

  test('真实传输 401：刷新后带新头重试并落盘', () async {
    final McpOAuthRuntime runtime = await runtimeFor(token());
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      if (requests.length == 1) return http.Response('expired', 401);
      return http.Response.bytes(
        utf8.encode('{"jsonrpc":"2.0","id":1,"result":{}}'),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final McpTransport transport = toMcpTransport(
      McpServerConfig(
        name: spec.name,
        type: McpTransportType.http,
        url: spec.url,
      ),
      authHeaders: runtime.headers,
      refreshAuth: runtime.refresh,
      client: client,
    );
    addTearDown(transport.disconnect);

    await transport.send(McpMessage.request(id: 1, method: 'tools/list'));

    expect(requests, hasLength(2));
    expect(requests.first.headers['Authorization'], 'Bearer access-1');
    expect(requests.last.headers['Authorization'], 'Bearer access-2');
    expect((await store.load('docs'))!.accessToken, 'access-2');
  });

  test('刷新失败：needs_auth，消息不含令牌，旧令牌保留', () async {
    final McpOAuthRuntime runtime = await runtimeFor(token());
    authServer.tokenStatus = 400;
    authServer.tokenResponse = <String, Object?>{
      'access_token': 'must-not-leak',
    };

    await expectLater(
      runtime.refresh(),
      throwsA(
        isA<McpException>()
            .having((McpException e) => e.code, 'code', 'needs_auth')
            .having(
              (McpException e) => e.message,
              'message',
              isNot(contains('must-not-leak')),
            ),
      ),
    );
    expect((await store.load('docs'))!.accessToken, 'access-1');
  });

  test('并发刷新单飞：只发一次 refresh_token', () async {
    final McpOAuthRuntime runtime = await runtimeFor(token());
    authServer.tokenDelay = const Duration(milliseconds: 100);

    final List<Map<String, String>> headers = await Future.wait(
      <Future<Map<String, String>>>[runtime.refresh(), runtime.refresh()],
    );

    expect(
      headers.map((Map<String, String> h) => h['Authorization']),
      everyElement('Bearer access-2'),
    );
    expect(authServer.tokenRequests, hasLength(1));
  });
}

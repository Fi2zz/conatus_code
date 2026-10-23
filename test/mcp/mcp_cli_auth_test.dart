/// `nava mcp auth / logout`：授权码流程、令牌落盘与登出。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/fake_oauth_server.dart';

void main() {
  late Directory dir;
  late String path;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-mcp-auth-');
    path = '${dir.path}${Platform.pathSeparator}config.toml';
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  McpCliDeps deps() => McpCliDeps(out: out, err: err);

  Future<int> run(List<String> args, {McpCliDeps? overrides}) =>
      runMcpCli(args, configPath: path, deps: overrides ?? deps());

  group('auth / logout', () {
    test('auth 完成授权并把令牌写入注入的存储', () async {
      final FakeOAuthServer authServer = await FakeOAuthServer.start();
      addTearDown(authServer.close);
      File(path).writeAsStringSync('''
[mcp.servers.docs]
type = "http"
url = "${authServer.issuer}/mcp"

[mcp.servers.docs.oauth]
client_id = "test-client"
''');
      final String tokenDir = '${dir.path}${Platform.pathSeparator}oauth';
      final McpOAuthStore store = McpOAuthStore(tokenDir);
      final McpOAuthSession session = McpOAuthSession(
        log: out.writeln,
        callbackTimeout: const Duration(seconds: 5),
      );
      addTearDown(session.close);

      final int code = await runMcpCli(
        <String>['auth', 'docs'],
        configPath: path,
        deps: McpCliDeps(
          out: out,
          err: err,
          session: session,
          oauthStore: store,
          openUrl: _clickAuthorize,
        ),
      );

      expect(code, 0, reason: err.toString());
      final McpOAuthToken? token = await store.load('docs');
      expect(token, isNotNull);
      expect(token!.accessToken, 'access-2');
      expect(out.toString(), contains('${authServer.issuer}/authorize'));
      expect(out.toString(), contains('code_challenge_method=S256'));
      expect(out.toString(), isNot(contains('access-2')));
      if (!Platform.isWindows) {
        expect(File(store.pathOf('docs')).statSync().mode & 0x1FF, 0x180);
      }
    });

    test('auth 未知 server 退出 2', () async {
      final int code = await run(<String>['auth', 'missing']);

      expect(code, 2);
      expect(err.toString(), contains('找不到 MCP server missing'));
    });

    test('auth stdio server 退出 2', () async {
      await run(<String>['add', 'fs', '--', 'npx', 'server']);

      final int code = await run(<String>['auth', 'fs']);

      expect(code, 2);
      expect(err.toString(), contains('stdio'));
    });

    test('logout 删除令牌文件且幂等', () async {
      final String tokenDir = '${dir.path}${Platform.pathSeparator}oauth';
      final McpOAuthStore store = McpOAuthStore(tokenDir);
      await store.save(
        'docs',
        const McpOAuthToken(accessToken: 'a', refreshToken: 'r'),
      );
      final McpCliDeps injected = McpCliDeps(
        out: out,
        err: err,
        oauthStore: store,
      );

      expect(await run(<String>['logout', 'docs'], overrides: injected), 0);
      expect(File(store.pathOf('docs')).existsSync(), isFalse);
      expect(await run(<String>['logout', 'docs'], overrides: injected), 0);
    });
  });
}

/// 模拟浏览器：立刻回打 loopback 回调，带合法 code 与 state。
void _clickAuthorize(Uri authorizeUrl) {
  final Map<String, String> query = authorizeUrl.queryParameters;
  final Uri redirect = Uri.parse(query['redirect_uri']!);
  final Uri callback = redirect.replace(
    queryParameters: <String, String>{
      'code': 'code-1',
      'state': query['state']!,
    },
  );
  unawaited(http.get(callback));
}

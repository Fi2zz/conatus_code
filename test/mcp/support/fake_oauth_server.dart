/// 装配期 OAuth 刷新用的本地假授权服务器（发现 + 令牌端点，不访问外网）。
library;

import 'dart:convert';
import 'dart:io';

/// 一台最小 AS：返回 protected-resource / AS 元数据，并记录 `/token` 表单。
class FakeOAuthServer {
  FakeOAuthServer._(this.server, this.issuer);

  /// 监听中的 HTTP server。
  final HttpServer server;

  /// issuer（`http://127.0.0.1:<port>`）。
  final Uri issuer;

  /// 令牌端点收到的表单（按请求顺序）。
  final List<Map<String, String>> tokenRequests = <Map<String, String>>[];

  /// 令牌端点返回的 HTTP 状态码。
  int tokenStatus = HttpStatus.ok;

  /// 令牌端点响应前的延迟（并发单飞测试用）。
  Duration tokenDelay = Duration.zero;

  /// 令牌端点返回的 JSON 体。
  Map<String, Object?> tokenResponse = <String, Object?>{
    'access_token': 'access-2',
    'refresh_token': 'refresh-2',
    'expires_in': 3600,
  };

  /// 启动假 AS；调用方负责 [close]。
  static Future<FakeOAuthServer> start() async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final FakeOAuthServer fake = FakeOAuthServer._(
      server,
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    switch (request.uri.path) {
      case '/.well-known/oauth-protected-resource':
        await _json(request, <String, Object?>{
          'resource': '$issuer/mcp',
          'authorization_servers': <String>['$issuer'],
        });
        break;
      case '/.well-known/oauth-authorization-server':
        await _json(request, <String, Object?>{
          'issuer': '$issuer',
          'authorization_endpoint': '$issuer/authorize',
          'token_endpoint': '$issuer/token',
        });
        break;
      case '/token':
        if (request.method != 'POST') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }
        tokenRequests.add(
          Uri.splitQueryString(await utf8.decoder.bind(request).join()),
        );
        if (tokenDelay > Duration.zero) await Future<void>.delayed(tokenDelay);
        request.response.statusCode = tokenStatus;
        await _json(request, tokenResponse);
        break;
      default:
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
    }
  }

  Future<void> _json(HttpRequest request, Map<String, Object?> body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}

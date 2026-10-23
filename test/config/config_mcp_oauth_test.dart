/// `[mcp.servers.*.oauth]` 的解析测试：开关、预注册凭据与非法取值。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_mcp/conatus_mcp.dart' show McpOAuthConfig;
import 'package:test/test.dart';

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-mcp-oauth');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File(
    '${dir.path}${Platform.pathSeparator}$kConfigFileName',
  );
  file.writeAsStringSync(content);
  return file.path;
}

ConatusCodeConfig _load(String toml) => loadConfig(path: _writeToml(toml));

void _expectError(String fragment, String toml) {
  expect(
    () => _load(toml),
    throwsA(
      isA<ConfigException>().having(
        (ConfigException error) => error.message,
        'message',
        contains(fragment),
      ),
    ),
  );
}

void main() {
  group('[mcp.servers.*.oauth]', () {
    test('远程缺省启用，stdio 忽略，oauth = false 关闭', () {
      final ConatusCodeConfig config = _load('''
[mcp.servers.local]
command = "npx"

[mcp.servers.disabled]
type = "http"
url = "https://disabled.example/mcp"
oauth = false

[mcp.servers.remote]
type = "http"
url = "https://remote.example/mcp"
''');

      expect(config.mcp.servers[0].oauthEnabled, isFalse);
      expect(config.mcp.servers[0].oauth, isNull);

      final McpServerSpec disabled = config.mcp.servers[1];
      expect(disabled.oauth!.enabled, isFalse);
      expect(disabled.oauthEnabled, isFalse);

      final McpServerSpec remote = config.mcp.servers[2];
      expect(remote.oauth, isNull);
      expect(remote.oauthEnabled, isTrue);
    });

    test('oauth 表解析 client_id / client_secret / scope / callback_port', () {
      final ConatusCodeConfig config = _load('''
[mcp.servers.remote]
type = "http"
url = "https://remote.example/mcp"

[mcp.servers.remote.oauth]
client_id = "client-1"
client_secret = "secret-1"
scope = "mcp offline_access"
callback_port = 7317
''');

      final McpOAuthConfig? oauth = config.mcp.servers.single.oauth;
      expect(oauth, isNotNull);
      expect(oauth!.enabled, isTrue);
      expect(oauth.clientId, 'client-1');
      expect(oauth.clientSecret, 'secret-1');
      expect(oauth.scope, 'mcp offline_access');
      expect(oauth.callbackPort, 7317);
      expect(oauth.clientConfigured, isTrue);
    });

    test('令牌目录固定在 NAVA_HOME/oauth，不落 .opencode', () {
      expect(
        resolveOAuthTokenDir(env: <String, String>{'NAVA_HOME': '/tmp/nava-x'}),
        '/tmp/nava-x/oauth',
      );
      expect(
        resolveOAuthTokenDir(env: <String, String>{'HOME': '/home/u'}),
        '/home/u/.nava/oauth',
      );
      expect(
        resolveOAuthTokenDir(env: <String, String>{'NAVA_HOME': '/tmp/nava-x'}),
        isNot(contains('.opencode')),
      );
    });

    test('oauth 表内 enabled = false 生效', () {
      final ConatusCodeConfig config = _load('''
[mcp.servers.remote]
type = "http"
url = "https://remote.example/mcp"

[mcp.servers.remote.oauth]
enabled = false
client_id = "client-1"
''');

      final McpServerSpec remote = config.mcp.servers.single;
      expect(remote.oauth!.enabled, isFalse);
      expect(remote.oauth!.clientId, 'client-1');
      expect(remote.oauthEnabled, isFalse);
    });

    test('oauth 非法取值 → ConfigException', () {
      _expectError('mcp.servers.remote.oauth 必须是布尔值或表', '''
[mcp.servers.remote]
type = "http"
url = "https://remote.example/mcp"
oauth = "yes"
''');
      _expectError('mcp.servers.remote.oauth.client_id 必须是字符串', '''
[mcp.servers.remote]
type = "http"
url = "https://remote.example/mcp"
[mcp.servers.remote.oauth]
client_id = 42
''');
      _expectError('mcp.servers.remote.oauth.enabled 必须是布尔值', '''
[mcp.servers.remote]
type = "http"
url = "https://remote.example/mcp"
[mcp.servers.remote.oauth]
enabled = "yes"
''');
      _expectError('mcp.servers.remote.oauth.callback_port 必须是 1-65535 的整数', '''
[mcp.servers.remote]
type = "http"
url = "https://remote.example/mcp"
[mcp.servers.remote.oauth]
callback_port = 0
''');
    });
  });
}

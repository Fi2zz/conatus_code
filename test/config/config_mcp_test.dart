/// `[mcp.servers.*]` 的解析测试：三种传输类型、必填校验、占位符原样保留。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-mcp-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}${Platform.pathSeparator}$kConfigFileName');
  file.writeAsStringSync(content);
  return file.path;
}

ConatusCodeConfig _load(String toml) => loadConfig(path: _writeToml(toml));

void _expectError(String fragment, String toml) {
  expect(
    () => _load(toml),
    throwsA(isA<ConfigException>().having(
        (ConfigException error) => error.message, 'message',
        contains(fragment))),
  );
}

void main() {
  group('[mcp.servers.*]', () {
    test('stdio / http / sse 三种类型完整解析，占位符原样保留', () {
      final ConatusCodeConfig config = _load('''
[mcp.servers.fs]
type = "stdio"
command = "npx"
args = ["-y", "server-filesystem", "/tmp"]
env = { API_KEY = "\${TAVILY_API_KEY}" }

[mcp.servers.remote]
type = "http"
url = "https://mcp.example.com/mcp"
headers = { Authorization = "Bearer \${REMOTE_TOKEN}" }

[mcp.servers.events]
type = "sse"
url = "https://mcp.example.com/sse"
''');

      expect(config.mcp.servers, hasLength(3));

      final McpServerSpec fs = config.mcp.servers[0];
      expect(fs.name, 'fs');
      expect(fs.type, McpServerType.stdio);
      expect(fs.command, 'npx');
      expect(fs.args, <String>['-y', 'server-filesystem', '/tmp']);
      expect(fs.env, <String, String>{'API_KEY': r'${TAVILY_API_KEY}'});

      final McpServerSpec remote = config.mcp.servers[1];
      expect(remote.name, 'remote');
      expect(remote.type, McpServerType.http);
      expect(remote.url, 'https://mcp.example.com/mcp');
      expect(remote.headers,
          <String, String>{'Authorization': r'Bearer ${REMOTE_TOKEN}'});

      final McpServerSpec events = config.mcp.servers[2];
      expect(events.type, McpServerType.sse);
      expect(events.url, 'https://mcp.example.com/sse');
    });

    test('type 缺省按 stdio；args / env / headers 缺省为空', () {
      final ConatusCodeConfig config = _load('''
[mcp.servers.fs]
command = "npx"
''');

      final McpServerSpec fs = config.mcp.servers.single;
      expect(fs.type, McpServerType.stdio);
      expect(fs.args, isEmpty);
      expect(fs.env, isEmpty);
      expect(fs.headers, isEmpty);
      expect(fs.url, isNull);
    });

    test('无 [mcp] 表时 servers 为空', () {
      final ConatusCodeConfig config = _load('[agent]\nmax_steps = 8\n');
      expect(config.mcp.servers, isEmpty);
    });

    test('stdio 缺 command → ConfigException', () {
      _expectError('mcp.servers.fs.command 不能为空', '''
[mcp.servers.fs]
type = "stdio"
''');
    });

    test('http / sse 缺 url → ConfigException', () {
      _expectError('mcp.servers.remote.url 不能为空', '''
[mcp.servers.remote]
type = "http"
''');
      _expectError('mcp.servers.events.url 不能为空', '''
[mcp.servers.events]
type = "sse"
''');
    });

    test('未知 type → ConfigException', () {
      _expectError('mcp.servers.x.type 取值 "ws" 不合法', '''
[mcp.servers.x]
type = "ws"
command = "npx"
''');
    });

    test('mcp.servers 非表 / server 非表 → ConfigException', () {
      _expectError('mcp.servers 必须是表', 'mcp = { servers = "x" }\n');
      _expectError('mcp.servers.fs 必须是表', '''
[mcp.servers]
fs = "npx"
''');
    });

    test('env / headers 非表或值非字符串 → ConfigException', () {
      _expectError('mcp.servers.fs.env 必须是表', '''
[mcp.servers.fs]
command = "npx"
env = "API_KEY"
''');
      _expectError('mcp.servers.fs.headers 的元素必须是字符串', '''
[mcp.servers.fs]
command = "npx"
headers = { Authorization = 42 }
''');
    });
  });
}

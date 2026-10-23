/// `[mcp.servers.<name>]` 段拼接：表头变体、替换、转义与 TOML 校验。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';
import 'package:toml/toml.dart';

void main() {
  group('appendMcpServerSection', () {
    test('远程 server：type 推导为 http，写 url', () {
      final String result = appendMcpServerSection(
        '[agent]\nmax_steps = 8\n',
        name: 'docs',
        url: 'https://mcp.example.com/mcp',
      );

      expect(result, startsWith('[agent]\nmax_steps = 8\n'));
      expect(result, contains('[mcp.servers.docs]'));
      expect(result, contains('type = "http"'));
      expect(result, contains('url = "https://mcp.example.com/mcp"'));
    });

    test('stdio：command + args，type 推导为 stdio', () {
      final String result = appendMcpServerSection(
        '',
        name: 'fs',
        command: <String>[
          'npx',
          '-y',
          '@modelcontextprotocol/server-filesystem',
        ],
      );

      expect(result, contains('[mcp.servers.fs]'));
      expect(result, contains('type = "stdio"'));
      expect(result, contains('command = "npx"'));
      expect(
        result,
        contains('args = [ "-y", "@modelcontextprotocol/server-filesystem" ]'),
      );
    });

    test('oauth 开关写成布尔字段', () {
      final String result = appendMcpServerSection(
        '',
        name: 'docs',
        url: 'https://example.com/mcp',
        oauth: false,
      );

      expect(result, contains('oauth = false'));
    });

    test('同名替换：不重复表头，嵌套 oauth 子表一并移除', () {
      const String toml = '''
[mcp.servers.docs]
type = "http"
url = "https://old.example.com/mcp"

[mcp.servers.docs.oauth]
client_id = "old-client"

[mcp.servers.other]
type = "http"
url = "https://other.example.com/mcp"
''';

      final String result = appendMcpServerSection(
        toml,
        name: 'docs',
        url: 'https://new.example.com/mcp',
      );

      expect(
        RegExp(r'\[mcp\.servers\.docs\]').allMatches(result),
        hasLength(1),
      );
      expect(result, isNot(contains('old.example.com')));
      expect(result, isNot(contains('old-client')));
      expect(result, contains('new.example.com'));
      expect(result, contains('[mcp.servers.other]'));
    });

    for (final ({String label, String header}) form
        in <({String label, String header})>[
          (label: '行尾注释', header: '[mcp.servers.docs] # 说明'),
          (label: '括号内空格', header: '[ mcp.servers.docs ]'),
          (label: '单引号键', header: "[mcp.servers.'docs']"),
          (label: '双引号键 + 注释', header: '[mcp.servers."docs"] # 说明'),
        ]) {
      test('识别表头变体：${form.label}', () {
        final String toml =
            '${form.header}\ntype = "http"\n'
            'url = "https://old.example.com/mcp"\n';

        final String result = appendMcpServerSection(
          toml,
          name: 'docs',
          url: 'https://new.example.com/mcp',
        );

        expect(result, contains('[mcp.servers.docs]'));
        expect(result, isNot(contains('old.example.com')));
        expect(() => TomlDocument.parse(result), returnsNormally);
      });
    }

    test('名字需要引号时用 TOML 引号键', () {
      final String result = appendMcpServerSection(
        '',
        name: 'team:docs',
        url: 'https://example.com/mcp',
      );

      expect(result, contains('[mcp.servers."team:docs"]'));
    });

    test('字符串里的反斜杠、引号与控制字符被转义', () {
      final String result = appendMcpServerSection(
        '',
        name: 'fs',
        command: <String>[r'C:\tools\node.exe', 'a"b', 'line\nbreak\ttab'],
      );

      expect(result, contains(r'command = "C:\\tools\\node.exe"'));
      expect(result, contains(r'"a\"b"'));
      expect(result, contains(r'"line\nbreak\ttab"'));
      expect(() => TomlDocument.parse(result), returnsNormally);
    });

    test('原文件无尾换行也不与新增段粘连', () {
      final String result = appendMcpServerSection(
        '[agent]\nmax_steps = 8',
        name: 'docs',
        url: 'https://example.com/mcp',
      );

      expect(result, startsWith('[agent]\nmax_steps = 8\n'));
      expect(() => TomlDocument.parse(result), returnsNormally);
    });

    test('server 段之后的数组表（[[permissions]]）不被吞掉', () {
      const String toml = '''
[mcp.servers.docs]
type = "http"
url = "https://old.example.com/mcp"

[[permissions]]
action = "shell"
effect = "deny"
''';

      final String result = appendMcpServerSection(
        toml,
        name: 'docs',
        url: 'https://new.example.com/mcp',
      );

      expect(result, contains('[[permissions]]'));
      expect(result, contains('action = "shell"'));
      expect(() => TomlDocument.parse(result), returnsNormally);
    });

    test('内联 servers 表产生重复键时抛 FormatException', () {
      const String toml =
          '[mcp]\nservers = { docs = { url = "https://old" } }\n';

      expect(
        () => appendMcpServerSection(
          toml,
          name: 'docs',
          url: 'https://new.example.com/mcp',
        ),
        throwsFormatException,
      );
    });

    test('既无 url 也无 command 抛 ArgumentError', () {
      expect(() => appendMcpServerSection('', name: 'x'), throwsArgumentError);
    });
  });
}

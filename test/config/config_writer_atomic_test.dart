/// 原子写配置与 `[mcp.servers.<name>]` 段拼接。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-atomic-');
    path = '${dir.path}${Platform.pathSeparator}config.toml';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('writeFileAtomic', () {
    test('写入内容并创建父目录', () {
      final String nested =
          '${dir.path}${Platform.pathSeparator}nested${Platform.pathSeparator}config.toml';

      writeFileAtomic(nested, '[llm]\n');

      expect(File(nested).readAsStringSync(), '[llm]\n');
    });

    test('不留临时文件', () {
      writeFileAtomic(path, 'x');

      expect(File(path).readAsStringSync(), 'x');
      expect(
        dir.listSync().map((FileSystemEntity entity) => entity.path),
        <String>[path],
      );
    });

    test('覆盖已有文件同样原子，不残留临时文件', () {
      writeFileAtomic(path, 'old');
      writeFileAtomic(path, 'new');

      expect(File(path).readAsStringSync(), 'new');
      expect(dir.listSync(), hasLength(1));
    });

    test('POSIX 下权限为 0600', () {
      writeFileAtomic(path, 'secret');

      if (Platform.isWindows) return;
      expect(File(path).statSync().mode & 0x1FF, 0x180);
    });

    test('显式 mode 生效', () {
      writeFileAtomic(path, 'x', mode: 0x1A4); // 0644

      if (Platform.isWindows) return;
      expect(File(path).statSync().mode & 0x1FF, 0x1A4);
    });
  });

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

    test('手写的引号键同名表也替换，不重复', () {
      const String toml =
          '[mcp.servers."docs"]\ntype = "http"\n'
          'url = "https://old.example.com/mcp"\n';

      final String result = appendMcpServerSection(
        toml,
        name: 'docs',
        url: 'https://new.example.com/mcp',
      );

      expect(
        RegExp(r'\[mcp\.servers\.(?:"docs"|docs)\]').allMatches(result),
        hasLength(1),
      );
      expect(result, isNot(contains('old.example.com')));
    });

    test('名字需要引号时用 TOML 引号键', () {
      final String result = appendMcpServerSection(
        '',
        name: 'team:docs',
        url: 'https://example.com/mcp',
      );

      expect(result, contains('[mcp.servers."team:docs"]'));
    });

    test('字符串里的反斜杠与引号被转义', () {
      final String result = appendMcpServerSection(
        '',
        name: 'fs',
        command: <String>[r'C:\tools\node.exe', r'a"b'],
      );

      expect(result, contains(r'command = "C:\\tools\\node.exe"'));
      expect(result, contains(r'"a\"b"'));
    });

    test('既无 url 也无 command 抛 ArgumentError', () {
      expect(() => appendMcpServerSection('', name: 'x'), throwsArgumentError);
    });
  });
}

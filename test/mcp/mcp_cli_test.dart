/// `nava mcp add / list` CLI：写入字段、权限、替换与只读列表。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late String path;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-mcp-cli-');
    path = '${dir.path}${Platform.pathSeparator}config.toml';
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  McpCliDeps deps() => McpCliDeps(out: out, err: err);

  Future<int> run(List<String> args, {McpCliDeps? overrides}) =>
      runMcpCli(args, configPath: path, deps: overrides ?? deps());

  group('add', () {
    test('--url 写入 [mcp.servers.<name>] 且权限 0600', () async {
      final int code = await run(<String>[
        'add',
        'docs',
        '--url',
        'https://mcp.example.com/mcp',
      ]);

      expect(code, 0);
      final String content = File(path).readAsStringSync();
      expect(content, contains('[mcp.servers.docs]'));
      expect(content, contains('type = "http"'));
      expect(content, contains('https://mcp.example.com/mcp'));
      if (!Platform.isWindows) {
        expect(File(path).statSync().mode & 0x1FF, 0x180);
      }
    });

    test('-- <command...> 写入 stdio server', () async {
      final int code = await run(<String>[
        'add',
        'fs',
        '--',
        'npx',
        '-y',
        'server-filesystem',
        '/tmp',
      ]);

      expect(code, 0);
      final String content = File(path).readAsStringSync();
      expect(content, contains('[mcp.servers.fs]'));
      expect(content, contains('type = "stdio"'));
      expect(content, contains('command = "npx"'));
      expect(content, contains('args = [ "-y", "server-filesystem", "/tmp" ]'));
    });

    test('同名再次 add 是替换，不产生第二个表头', () async {
      await run(<String>['add', 'docs', '--url', 'https://old.example.com/a']);
      final int code = await run(<String>[
        'add',
        'docs',
        '--url',
        'https://new.example.com/b',
      ]);

      expect(code, 0);
      final String content = File(path).readAsStringSync();
      expect(
        RegExp(r'\[mcp\.servers\.docs\]').allMatches(content),
        hasLength(1),
      );
      expect(content, isNot(contains('old.example.com')));
      expect(content, contains('new.example.com'));
    });

    test('已有配置的其余内容保留', () async {
      File(path).writeAsStringSync('[agent]\nmax_steps = 8\n');

      await run(<String>['add', 'docs', '--url', 'https://example.com/mcp']);

      final String content = File(path).readAsStringSync();
      expect(content, contains('[agent]\nmax_steps = 8'));
    });

    test('--no-oauth 写 oauth = false', () async {
      await run(<String>[
        'add',
        'docs',
        '--no-oauth',
        '--url',
        'https://example.com/mcp',
      ]);

      expect(File(path).readAsStringSync(), contains('oauth = false'));
    });

    test('拒绝写入 .opencode 且不创建文件', () async {
      final String protectedPath =
          '${dir.path}${Platform.pathSeparator}.opencode'
          '${Platform.pathSeparator}config.toml';

      final int code = await runMcpCli(
        <String>['add', 'docs', '--url', 'https://example.com/mcp'],
        configPath: protectedPath,
        deps: deps(),
      );

      expect(code, 2);
      expect(File(protectedPath).existsSync(), isFalse);
      expect(err.toString(), contains('.opencode'));
    });
  });

  group('list', () {
    test('打印 name / type / url 与 command，不连接 server', () async {
      await run(<String>[
        'add',
        'docs',
        '--url',
        'https://mcp.example.com/mcp',
      ]);
      await run(<String>['add', 'fs', '--', 'npx', 'server-filesystem']);
      out.clear();

      final int code = await run(<String>['list']);

      expect(code, 0);
      final List<String> lines = out.toString().trim().split('\n');
      expect(lines, hasLength(2));
      expect(lines[0], 'docs\thttp\thttps://mcp.example.com/mcp');
      expect(lines[1], 'fs\tstdio\tnpx server-filesystem');
    });

    test('空配置提示且退出 0，不创建配置文件', () async {
      final int code = await run(<String>['list']);

      expect(code, 0);
      expect(out.toString(), contains('没有配置 MCP server'));
      expect(File(path).existsSync(), isFalse);
    });
  });
}

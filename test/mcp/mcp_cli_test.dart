/// `nava mcp add / list`：字段写入、权限、替换与只读列表。
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

    test('拒绝非 http(s) 的 --url', () async {
      final int code = await run(<String>[
        'add',
        'docs',
        '--url',
        'file:///tmp/config.toml',
      ]);

      expect(code, 2);
      expect(err.toString(), contains('http'));
      expect(File(path).existsSync(), isFalse);
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

    test('同名再次 add 是替换，不产生第二个表头并给出提示', () async {
      await run(<String>['add', 'docs', '--url', 'https://old.example.com/a']);
      out.clear();
      err.clear();
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
      expect(err.toString(), contains('已替换'));
      expect(err.toString(), contains('headers'));
    });

    test('已有配置的其余内容与无尾换行原样保留', () async {
      File(path).writeAsStringSync('[agent]\nmax_steps = 8');

      await run(<String>['add', 'docs', '--url', 'https://example.com/mcp']);

      final String content = File(path).readAsStringSync();
      expect(content, startsWith('[agent]\nmax_steps = 8\n'));
      expect(content, contains('[mcp.servers.docs]'));
    });

    test('--no-oauth / --oauth 写布尔开关', () async {
      await run(<String>[
        'add',
        'docs',
        '--no-oauth',
        '--url',
        'https://example.com/mcp',
      ]);
      await run(<String>[
        'add',
        'net',
        '--oauth',
        '--url',
        'https://net.example.com/mcp',
      ]);

      final String content = File(path).readAsStringSync();
      expect(content, contains('oauth = false'));
      expect(content, contains('oauth = true'));
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

    test('合并项目 .mcp.json，TOML 同名优先', () async {
      File(path).writeAsStringSync('''
[agent]
workdir = "${dir.path}"

[mcp.servers.toml]
command = "npx"
''');
      File('${dir.path}${Platform.pathSeparator}.mcp.json').writeAsStringSync(
        '{"mcpServers":{"json":{"command":"node","args":["server.js"]},'
        '"toml":{"command":"ignored"}}}',
      );
      out.clear();

      final int code = await run(<String>['list']);

      expect(code, 0);
      expect(out.toString(), contains('toml\tstdio\tnpx'));
      expect(out.toString(), contains('json\tstdio\tnode server.js'));
      expect(out.toString(), isNot(contains('ignored')));
      expect(err.toString(), contains('toml'));
    });

    test('带空白的命令参数加引号', () async {
      await run(<String>[
        'add',
        'fs',
        '--',
        'node',
        '/path with space/server.js',
      ]);
      out.clear();

      await run(<String>['list']);

      expect(out.toString(), contains('node "/path with space/server.js"'));
    });

    test('空配置 / 只有其他表时提示，不创建文件', () async {
      expect(await run(<String>['list']), 0);
      expect(out.toString(), contains('没有配置 MCP server'));
      expect(File(path).existsSync(), isFalse);

      File(path).writeAsStringSync('[agent]\nmax_steps = 8\n');
      out.clear();
      expect(await run(<String>['list']), 0);
      expect(out.toString(), contains('没有配置 MCP server'));
    });
  });

  test('mcp --config <路径> 指定配置文件', () async {
    final String custom = '${dir.path}${Platform.pathSeparator}custom.toml';

    final int code = await runMcpCli(<String>[
      '--config',
      custom,
      'add',
      'docs',
      '--url',
      'https://x.test/mcp',
    ], deps: deps());

    expect(code, 0);
    expect(File(custom).readAsStringSync(), contains('[mcp.servers.docs]'));
    expect(File(path).existsSync(), isFalse);
  });
}

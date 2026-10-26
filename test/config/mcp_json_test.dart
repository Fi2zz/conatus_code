/// `.mcp.json`（Claude Code / OpenCode 生态）读取与合并。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

Directory _temp() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-mcp-json-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void _writeJson(Directory dir, Object value) {
  File('${dir.path}${Platform.pathSeparator}.mcp.json')
      .writeAsStringSync(jsonEncode(value));
}

String _path(Directory dir, String relative) =>
    '${dir.path}${Platform.pathSeparator}'
    '${relative.replaceAll('/', Platform.pathSeparator)}';

void main() {
  test('没有 .mcp.json 时返回空列表且不告警', () {
    final Directory dir = _temp();
    final List<String> warnings = <String>[];

    final List<McpServerSpec> specs = loadMcpJsonSpecs(
      workdir: dir.path,
      onWarning: warnings.add,
    );

    expect(specs, isEmpty);
    expect(warnings, isEmpty);
  });

  test('stdio / http / 仅 url 的条目都能解析', () {
    final Directory dir = _temp();
    _writeJson(dir, <String, Object?>{
      'mcpServers': <String, Object?>{
        'filesystem': <String, Object?>{
          'command': 'npx',
          'args': <String>['-y', '@modelcontextprotocol/server-filesystem'],
          'env': <String, String>{'TOKEN': r'${TOKEN}'},
        },
        'remote': <String, Object?>{
          'type': 'http',
          'url': 'https://mcp.example.com/mcp',
          'headers': <String, String>{'Authorization': r'Bearer ${TOKEN}'},
        },
        'sse': <String, Object?>{
          'type': 'sse',
          'url': 'https://sse.example.com/sse',
        },
        'url-only': <String, Object?>{
          'url': 'https://url-only.example.com/mcp',
        },
      },
    });

    final List<McpServerSpec> specs = loadMcpJsonSpecs(workdir: dir.path);
    final Map<String, McpServerSpec> byName = <String, McpServerSpec>{
      for (final McpServerSpec spec in specs) spec.name: spec,
    };

    expect(specs, hasLength(4));
    expect(byName['filesystem']!.type, McpServerType.stdio);
    expect(byName['filesystem']!.command, 'npx');
    expect(byName['filesystem']!.args, <String>[
      '-y',
      '@modelcontextprotocol/server-filesystem',
    ]);
    expect(byName['filesystem']!.env['TOKEN'], r'${TOKEN}');
    expect(byName['remote']!.type, McpServerType.http);
    expect(byName['remote']!.headers['Authorization'], r'Bearer ${TOKEN}');
    expect(byName['sse']!.type, McpServerType.sse);
    expect(byName['url-only']!.type, McpServerType.http);
  });

  test('从工作目录向上找到项目根的 .mcp.json', () {
    final Directory root = _temp();
    Directory(_path(root, '.git')).createSync();
    Directory(_path(root, 'packages/app')).createSync(recursive: true);
    _writeJson(root, <String, Object?>{
      'mcpServers': <String, Object?>{
        'root-server': <String, Object?>{'command': 'npx'},
      },
    });

    final List<McpServerSpec> specs = loadMcpJsonSpecs(
      workdir: _path(root, 'packages/app'),
    );

    expect(specs.single.name, 'root-server');
  });

  test('工作树 / 子模块的 .git 文件也算项目根', () {
    final Directory root = _temp();
    File(_path(root, '.git')).writeAsStringSync('gitdir: /tmp/worktree\n');
    Directory(_path(root, 'packages/app')).createSync(recursive: true);
    _writeJson(root, <String, Object?>{
      'mcpServers': <String, Object?>{
        'worktree-server': <String, Object?>{'command': 'npx'},
      },
    });

    final List<McpServerSpec> specs = loadMcpJsonSpecs(
      workdir: _path(root, 'packages/app'),
    );

    expect(specs.single.name, 'worktree-server');
  });

  test('坏条目跳过并告警，好条目照常加载', () {
    final Directory dir = _temp();
    _writeJson(dir, <String, Object?>{
      'mcpServers': <String, Object?>{
        'not-a-table': 3,
        'no-command': <String, Object?>{'type': 'stdio'},
        'ok': <String, Object?>{'command': 'npx'},
      },
    });
    final List<String> warnings = <String>[];

    final List<McpServerSpec> specs = loadMcpJsonSpecs(
      workdir: dir.path,
      onWarning: warnings.add,
    );

    expect(specs.map((McpServerSpec spec) => spec.name), <String>['ok']);
    expect(warnings, hasLength(3));
    expect(warnings.join('\n'), contains('not-a-table'));
    expect(warnings.join('\n'), contains('no-command'));
    expect(warnings.join('\n'), contains('来源可信'));
  });

  test('损坏的 JSON 告警并返回空列表', () {
    final Directory dir = _temp();
    File(_path(dir, '.mcp.json')).writeAsStringSync('{ not json');
    final List<String> warnings = <String>[];

    final List<McpServerSpec> specs = loadMcpJsonSpecs(
      workdir: dir.path,
      onWarning: warnings.add,
    );

    expect(specs, isEmpty);
    expect(warnings.single, contains('.mcp.json'));
  });

  test('config.toml 同名条目优先，.mcp.json 只补缺', () {
    const McpServerSpec toml = McpServerSpec(
      name: 'shared',
      type: McpServerType.stdio,
      command: 'from-toml',
    );
    const McpServerSpec json = McpServerSpec(
      name: 'shared',
      type: McpServerType.stdio,
      command: 'from-json',
    );
    const McpServerSpec extra = McpServerSpec(
      name: 'extra',
      type: McpServerType.http,
      url: 'https://example.com/mcp',
    );
    final List<String> warnings = <String>[];

    final List<McpServerSpec> merged = mergeMcpServerSpecs(
      <McpServerSpec>[toml],
      <McpServerSpec>[json, extra],
      onWarning: warnings.add,
    );

    expect(merged.map((McpServerSpec spec) => spec.name), <String>[
      'shared',
      'extra',
    ]);
    expect(merged.first.command, 'from-toml');
    expect(warnings.single, contains('shared'));
  });

  test('loadEffectiveMcpServers 用配置的 workdir 读取 .mcp.json', () {
    final Directory dir = _temp();
    _writeJson(dir, <String, Object?>{
      'mcpServers': <String, Object?>{
        'json-server': <String, Object?>{'command': 'npx'},
      },
    });
    final File config = File(_path(dir, 'config.toml'));
    config.writeAsStringSync('''
[agent]
workdir = "${dir.path}"

[mcp.servers.toml-server]
command = "npx"
''');
    final ConatusCodeConfig loaded = loadConfig(path: config.path);

    final List<McpServerSpec> specs = loadEffectiveMcpServers(config: loaded);

    expect(specs.map((McpServerSpec spec) => spec.name), <String>[
      'toml-server',
      'json-server',
    ]);
  });

  test('全局 Claude Desktop 配置：读取与优先级', () {
    final Directory home = _temp();
    final Directory work = _temp();
    final File desktop = File(
      _path(
        home,
        'Library/Application Support/Claude/claude_desktop_config.json',
      ),
    )..parent.createSync(recursive: true);
    desktop.writeAsStringSync(
      '{"mcpServers":{"desktop":{"command":"npx"},"shared":{"command":"desktop"}}}',
    );
    _writeJson(work, <String, Object?>{
      'mcpServers': <String, Object?>{
        'project': <String, Object?>{'command': 'npx'},
        'shared': <String, Object?>{'command': 'project'},
      },
    });
    final File config = File(_path(work, 'config.toml'));
    config.writeAsStringSync('''
[agent]
workdir = "${work.path}"

[mcp.servers.toml]
command = "npx"

[mcp.servers.shared]
command = "toml"
''');
    final ConatusCodeConfig loaded = loadConfig(path: config.path);

    final List<McpServerSpec> global = loadClaudeDesktopMcpSpecs(
      homeDir: home.path,
    );
    expect(global.map((McpServerSpec spec) => spec.name), <String>[
      'desktop',
      'shared',
    ]);

    final List<McpServerSpec> merged = loadEffectiveMcpServers(
      config: loaded,
      workdir: work.path,
      homeDir: home.path,
      includeClaudeDesktop: true,
    );
    expect(merged.map((McpServerSpec spec) => spec.name), <String>[
      'toml',
      'shared',
      'project',
      'desktop',
    ]);
    expect(
      merged.firstWhere((McpServerSpec spec) => spec.name == 'shared').command,
      'toml',
    );
  });
}

/// `nava mcp` 的失败路径：只读目录、坏 TOML、I/O 错误与用法。
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
    dir = Directory.systemTemp.createTempSync('nava-mcp-err-');
    path = '${dir.path}${Platform.pathSeparator}config.toml';
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  McpCliDeps deps() => McpCliDeps(out: out, err: err);

  Future<int> run(List<String> args, {String? configPath}) =>
      runMcpCli(args, configPath: configPath ?? path, deps: deps());

  group('只读目录', () {
    for (final String protectedPath in <String>[
      '.opencode/config.toml',
      '.config/opencode/config.toml',
    ]) {
      test('拒绝 $protectedPath 且不创建文件', () async {
        final String target =
            '${dir.path}${Platform.pathSeparator}$protectedPath';

        final int code = await run(<String>[
          'add',
          'docs',
          '--url',
          'https://example.com/mcp',
        ], configPath: target);

        expect(code, 2);
        expect(File(target).existsSync(), isFalse);
        expect(err.toString(), contains('只读'));
      });
    }

    test('父目录是符号链接指向 .opencode 时拒绝', () async {
      final Directory protectedDir = Directory(
        '${dir.path}${Platform.pathSeparator}.opencode',
      )..createSync();
      final String linkPath = '${dir.path}${Platform.pathSeparator}link';
      Link(linkPath).createSync(protectedDir.path);
      final String target = '$linkPath${Platform.pathSeparator}config.toml';

      final int code = await run(<String>[
        'add',
        'docs',
        '--url',
        'https://example.com/mcp',
      ], configPath: target);

      expect(code, 2);
      expect(File(target).existsSync(), isFalse);
      expect(err.toString(), contains('只读'));
    });

    test('相对路径 .opencode/config.toml 同样拒绝', () async {
      final int code = await run(<String>[
        'add',
        'docs',
        '--url',
        'https://example.com/mcp',
      ], configPath: '.opencode/config.toml');

      expect(code, 2);
      expect(File('.opencode/config.toml').existsSync(), isFalse);
    });
  });

  test('坏 TOML 导致重复键：退出 2 且原字节不变', () async {
    const String broken =
        '[mcp]\nservers = { docs = { url = "https://old" } }\n';
    File(path).writeAsStringSync(broken);

    final int code = await run(<String>[
      'add',
      'docs',
      '--url',
      'https://new.example.com/mcp',
    ]);

    expect(code, 2);
    expect(File(path).readAsStringSync(), broken);
    expect(err.toString(), contains('配置写入失败'));
  });

  test('目标目录只读：退出 2 且原文件不变', () async {
    if (Platform.isWindows) return;
    final Directory locked = Directory(
      '${dir.path}${Platform.pathSeparator}locked',
    )..createSync();
    final String lockedPath =
        '${locked.path}${Platform.pathSeparator}config.toml';
    const String original = '[agent]\nmax_steps = 8\n';
    File(lockedPath).writeAsStringSync(original);
    Process.runSync('chmod', <String>['500', locked.path]);
    addTearDown(() => Process.runSync('chmod', <String>['700', locked.path]));
    final File probe = File('${locked.path}${Platform.pathSeparator}probe');
    try {
      probe.writeAsStringSync('x');
      probe.deleteSync();
      return; // 特权用户不受 0500 限制，跳过。
    } on FileSystemException {
      // 预期：目录只读。
    }

    final int code = await run(<String>[
      'add',
      'docs',
      '--url',
      'https://example.com/mcp',
    ], configPath: lockedPath);

    expect(code, 2);
    expect(File(lockedPath).readAsStringSync(), original);
    expect(err.toString(), contains('配置读写失败'));
  });

  group('用法', () {
    test('--help 退出 0 并提到 mcp 子命令与选项', () async {
      final int code = await run(<String>['--help']);

      expect(code, 0);
      expect(out.toString(), contains('nava mcp'));
      expect(out.toString(), contains('--oauth'));
      expect(out.toString(), contains('--global'));
      expect(out.toString(), contains('--config'));
    });

    test('缺子命令 / 未知子命令 / 缺参数 / --config 缺值均退出 2', () async {
      expect(await run(<String>[]), 2);
      expect(await run(<String>['nope']), 2);
      expect(await run(<String>['add']), 2);
      expect(await run(<String>['add', 'docs']), 2);
      expect(await run(<String>['add', 'docs', '--url']), 2);
      expect(await run(<String>['add', 'docs', '--']), 2);
      expect(await run(<String>['--config']), 2);
      expect(await run(<String>['auth']), 2);
      expect(await run(<String>['logout']), 2);
      expect(File(path).existsSync(), isFalse);
    });
  });
}

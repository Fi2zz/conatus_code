/// `instructions` 配置项：路径 / glob / URL / `~` 展开与失败跳过。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

final String _sep = Platform.pathSeparator;

String _dir(String prefix) {
  final Directory dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir.path;
}

void _write(String base, List<String> parts, String content) {
  final String path = <String>[base, ...parts].join(_sep);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

InstructionLoader _loader(String workdir, List<String> extra, {String? home}) {
  final InstructionLoader loader = InstructionLoader(
    workdir: workdir,
    home: home,
    extra: extra,
  );
  addTearDown(loader.dispose);
  return loader;
}

void main() {
  late HttpServer server;
  late String remote;
  late int requests;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    remote = 'http://127.0.0.1:${server.port}/AGENTS.md';
    requests = 0;
    server.listen((HttpRequest request) async {
      requests++;
      request.response.write('REMOTE-$request');
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('路径、glob 与 URL 依次追加在 AGENTS.md 之后', () async {
    final String root = _dir('nava-extra-');
    _write(root, <String>['AGENTS.md'], 'PROJECT');
    _write(root, <String>['CONTRIBUTING.md'], 'CONTRIB');
    _write(root, <String>['docs', 'guide.md'], 'GUIDE');

    final String? text = await _loader(root, <String>[
      'CONTRIBUTING.md',
      'docs/*.md',
      remote,
    ]).compose();

    expect(text, isNotNull);
    expect(text!.indexOf('PROJECT'), lessThan(text.indexOf('CONTRIB')));
    expect(text.indexOf('CONTRIB'), lessThan(text.indexOf('GUIDE')));
    expect(text.indexOf('GUIDE'), lessThan(text.indexOf('REMOTE-')));
  });

  test('URL 内容按会话缓存：重复 compose 只请求一次', () async {
    final String root = _dir('nava-url-cache-');
    final InstructionLoader loader = _loader(root, <String>[remote]);

    expect(await loader.compose(), contains('REMOTE-'));
    expect(await loader.compose(), contains('REMOTE-'));
    expect(requests, 1);
  });

  test('`~` 展开到用户目录', () async {
    final String home = _dir('nava-home-');
    _write(home, <String>['notes.md'], 'HOME-NOTE');

    final String? text = await _loader(_dir('nava-work-'), <String>[
      '~/notes.md',
    ], home: home).compose();

    expect(text, contains('HOME-NOTE'));
  });

  test('缺失文件与不可达 URL 静默跳过', () async {
    final String root = _dir('nava-missing-extra-');

    final String? text = await _loader(root, <String>[
      'nope.md',
      'missing/*.md',
      'http://127.0.0.1:1/unreachable.md',
    ]).compose();

    expect(text, isNull);
  });

  test('URL 超时按失败跳过（不阻塞其余来源）', () async {
    final String root = _dir('nava-url-timeout-');
    _write(root, <String>['AGENTS.md'], 'LOCAL');
    // 只连不回的端口：accept 后不写响应，触发 5 秒读取超时。
    final HttpServer silent = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    silent.listen((HttpRequest request) {});
    addTearDown(() => silent.close(force: true));

    final String? text = await _loader(root, <String>[
      'http://127.0.0.1:${silent.port}/slow.md',
    ]).compose();

    expect(text, contains('LOCAL'));
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('相对路径以 workdir 为基准，绝对路径例外放行', () async {
    final String root = _dir('nava-abs-');
    final String outside = _dir('nava-abs-out-');
    _write(outside, <String>['note.md'], 'ABSOLUTE-OK');

    final String? text = await _loader(root, <String>[
      <String>[outside, 'note.md'].join(_sep),
    ]).compose();

    expect(text, contains('ABSOLUTE-OK'));
  });

  test('相对路径的符号链接越界 → 跳过', () async {
    if (Platform.isWindows) return;
    final String root = _dir('nava-extra-link-');
    final String outside = _dir('nava-extra-out-');
    _write(outside, <String>['secret.md'], 'LEAKED');
    Link('$root${_sep}link.md').createSync('$outside${_sep}secret.md');

    expect(await _loader(root, <String>['link.md']).compose(), isNull);
  });
}

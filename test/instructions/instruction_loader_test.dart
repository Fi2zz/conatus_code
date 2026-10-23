/// `InstructionLoader`：全局 / 项目 / 嵌套层级、去重、符号链接与上限。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

final String _sep = Platform.pathSeparator;

/// 建临时目录，测试结束自动删除。
String _dir(String prefix) {
  final Directory dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir.path;
}

/// 在 [base] 下按 [parts] 建目录并写文件。
void _write(String base, List<String> parts, String content) {
  final String path = <String>[base, ...parts].join(_sep);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

InstructionLoader _loader(String workdir, {String? home}) {
  final InstructionLoader loader = InstructionLoader(
    workdir: workdir,
    home: home,
  );
  addTearDown(loader.dispose);
  return loader;
}

void main() {
  test('全局 → 项目根 → 工作目录 → 嵌套，由远及近', () async {
    final String home = _dir('nava-home-');
    _write(home, <String>['.nava', 'AGENTS.md'], 'GLOBAL-NAVA');
    _write(home, <String>[
      '.config',
      'opencode',
      'AGENTS.md',
    ], 'GLOBAL-OPENCODE');
    final String root = _dir('nava-root-');
    Directory('$root$_sep.git').createSync();
    _write(root, <String>['AGENTS.md'], 'ROOT');
    final String sub = <String>[root, 'pkg'].join(_sep);
    _write(sub, <String>['AGENTS.md'], 'SUB');
    final String deep = <String>[sub, 'lib', 'deep'].join(_sep);
    _write(deep, <String>['AGENTS.md'], 'NESTED');

    final InstructionLoader loader = _loader(sub, home: home);
    await loader.notePath(<String>[deep, 'a.dart'].join(_sep));
    final String? text = await loader.compose();

    expect(text, isNotNull);
    expect(
      text!.indexOf('GLOBAL-NAVA'),
      lessThan(text.indexOf('GLOBAL-OPENCODE')),
    );
    expect(text.indexOf('GLOBAL-OPENCODE'), lessThan(text.indexOf('ROOT')));
    expect(text.indexOf('ROOT'), lessThan(text.indexOf('SUB')));
    expect(text.indexOf('SUB'), lessThan(text.indexOf('NESTED')));
  });

  test('同一层 AGENTS.md 在前、NAVA.md 在后', () async {
    final String root = _dir('nava-order-');
    Directory('$root$_sep.git').createSync();
    _write(root, <String>['AGENTS.md'], 'AGENT-TEXT');
    _write(root, <String>['NAVA.md'], 'NAVA-TEXT');

    final String? text = await _loader(
      root,
      home: _dir('nava-home-'),
    ).compose();

    expect(text, isNotNull);
    expect(text!.indexOf('AGENT-TEXT'), lessThan(text.indexOf('NAVA-TEXT')));
  });

  test('嵌套文件最近优先，且每文件只加载一次', () async {
    final String root = _dir('nava-nested-');
    Directory('$root$_sep.git').createSync();
    _write(root, <String>['AGENTS.md'], 'ROOT');
    _write(root, <String>['pkg', 'AGENTS.md'], 'MID');
    _write(root, <String>['pkg', 'a', 'AGENTS.md'], 'NEAR');
    _write(root, <String>['pkg', 'a', 'deep', 'AGENTS.md'], 'DEEP');

    final InstructionLoader loader = _loader(
      <String>[root, 'pkg'].join(_sep),
      home: _dir('nava-home-'),
    );
    await loader.notePath(
      <String>[root, 'pkg', 'a', 'deep', 'x.dart'].join(_sep),
    );
    await loader.notePath(
      <String>[root, 'pkg', 'a', 'deep', 'x.dart'].join(_sep),
    );
    final String? text = await loader.compose();

    expect(text!.indexOf('DEEP'), lessThan(text.indexOf('NEAR')));
    expect(text.indexOf('MID'), lessThan(text.indexOf('DEEP')));
    expect(RegExp('NEAR').allMatches(text), hasLength(1));
  });

  test('去重：项目 AGENTS.md 与 instructions 同名只出现一次', () async {
    final String root = _dir('nava-dedup-');
    _write(root, <String>['AGENTS.md'], 'UNIQUE-MARK');
    final InstructionLoader loader = InstructionLoader(
      workdir: root,
      home: _dir('nava-home-'),
      extra: const <String>['AGENTS.md', 'AGENTS.md'],
    );
    addTearDown(loader.dispose);

    final String? text = await loader.compose();

    expect(RegExp('UNIQUE-MARK').allMatches(text!), hasLength(1));
  });

  test('符号链接指向工作区外 → 整个 AGENTS.md 不读', () async {
    if (Platform.isWindows) return;
    final String root = _dir('nava-link-');
    final String outside = _dir('nava-outside-');
    _write(outside, <String>['secret.md'], 'LEAKED');
    Link('$root${_sep}AGENTS.md').createSync('$outside${_sep}secret.md');

    final String? text = await _loader(
      root,
      home: _dir('nava-home-'),
    ).compose();

    expect(text, isNull);
  });

  test('全局文件是外链也照读（用户显式配置的例外）', () async {
    if (Platform.isWindows) return;
    final String home = _dir('nava-home-');
    final String outside = _dir('nava-outside-');
    _write(outside, <String>['shared.md'], 'GLOBAL-LINK');
    Directory('$home$_sep.nava').createSync();
    Link(
      '$home$_sep.nava${_sep}AGENTS.md',
    ).createSync('$outside${_sep}shared.md');

    final String? text = await _loader(
      _dir('nava-work-'),
      home: home,
    ).compose();

    expect(text, contains('GLOBAL-LINK'));
  });
}

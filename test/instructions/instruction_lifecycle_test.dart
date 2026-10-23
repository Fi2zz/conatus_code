/// `InstructionLoader` 生命周期：并发合并、dispose、嵌套重读。
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

InstructionLoader _loader(String workdir, {String? home}) {
  final InstructionLoader loader = InstructionLoader(
    workdir: workdir,
    home: home,
  );
  addTearDown(loader.dispose);
  return loader;
}

void main() {
  test('compose 并发调用合并为同一趟', () async {
    final String root = _dir('nava-coalesce-');
    _write(root, <String>['AGENTS.md'], 'COALESCE');
    final InstructionLoader loader = _loader(root, home: _dir('nava-home-'));

    final Future<String?> first = loader.compose();
    final Future<String?> second = loader.compose();

    expect(identical(first, second), isTrue);
    expect(await first, contains('COALESCE'));
  });

  test('dispose 后 compose 返回 null、notePath 不再记录', () async {
    final String root = _dir('nava-dispose-');
    final String file = <String>[root, 'a.dart'].join(_sep);
    _write(root, <String>['AGENTS.md'], 'BEFORE-DISPOSE');
    final InstructionLoader loader = InstructionLoader(
      workdir: root,
      home: _dir('nava-home-'),
    );

    expect(await loader.compose(), contains('BEFORE-DISPOSE'));
    loader.dispose();

    expect(loader.current, isNull);
    expect(await loader.compose(), isNull);
    expect(await loader.notePath(file), isFalse);
  });

  test('嵌套 AGENTS.md 在 compose 时重读（不冻结首次内容）', () async {
    final String root = _dir('nava-reread-');
    final String sub = <String>[root, 'pkg'].join(_sep);
    _write(sub, <String>['AGENTS.md'], 'OLD-NESTED');
    final InstructionLoader loader = _loader(root, home: _dir('nava-home-'));
    final String file = <String>[sub, 'a.dart'].join(_sep);

    expect(await loader.notePath(file), isTrue);
    expect(await loader.compose(), contains('OLD-NESTED'));

    _write(sub, <String>['AGENTS.md'], 'NEW-NESTED');

    final String? text = await loader.compose();
    expect(text, contains('NEW-NESTED'));
    expect(text, isNot(contains('OLD-NESTED')));
  });
}

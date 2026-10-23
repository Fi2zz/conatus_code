/// `InstructionLoader`：单文件 / 总量上限、`.opencode` 只读与缺失目录。
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
  test('单文件超 16 KiB 截断并标注', () async {
    final String root = _dir('nava-cap-');
    _write(root, <String>['AGENTS.md'], 'x' * (kInstructionMaxChars + 100));

    final String? text = await _loader(
      root,
      home: _dir('nava-home-'),
    ).compose();

    expect(text!.length, lessThanOrEqualTo(kInstructionMaxChars + 100));
    expect(text, endsWith('（已截断，原文超长）'));
  });

  test('总量超 64 KiB 截断并标注', () async {
    final String root = _dir('nava-total-');
    final List<String> extra = <String>[];
    for (int i = 0; i < 5; i++) {
      final String name = 'part$i.md';
      _write(root, <String>[name], 'p$i'.padRight(15000, 'y'));
      extra.add(name);
    }
    final InstructionLoader loader = InstructionLoader(
      workdir: root,
      home: _dir('nava-home-'),
      extra: extra,
    );
    addTearDown(loader.dispose);

    final String? text = await loader.compose();

    expect(text!.length, lessThanOrEqualTo(kInstructionTotalMaxChars + 100));
    expect(text, endsWith('（总长度已截断）'));
  });

  test('.opencode 目录只读：不加载也不改写', () async {
    final String root = _dir('nava-opencode-');
    _write(root, <String>['.opencode', 'AGENTS.md'], 'OPENCODE-ONLY');
    final File file = File('$root$_sep.opencode${_sep}AGENTS.md');
    final DateTime before = file.lastModifiedSync();

    final String? text = await _loader(
      root,
      home: _dir('nava-home-'),
    ).compose();

    expect(text, isNull);
    expect(file.readAsStringSync(), 'OPENCODE-ONLY');
    expect(file.lastModifiedSync(), before);
  });

  test('工作目录不存在时不抛错', () async {
    final String missing =
        '${Directory.systemTemp.path}${_sep}nope-${DateTime.now().microsecondsSinceEpoch}';

    expect(await _loader(missing, home: _dir('nava-home-')).compose(), isNull);
  });
}

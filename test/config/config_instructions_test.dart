/// 顶层 `instructions`：字符串数组解析与缺省值。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

ConatusCodeConfig _load(String toml) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-instr-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String path = '${dir.path}${Platform.pathSeparator}$kConfigFileName';
  File(path).writeAsStringSync(toml);
  return loadConfig(path: path);
}

void main() {
  test('instructions 缺省为空列表', () {
    expect(_load('').instructions, isEmpty);
  });

  test('instructions 按书写顺序解析', () {
    final ConatusCodeConfig config = _load(
      'instructions = [ "AGENTS.md", "docs/*.md", "https://example.com/a.md" ]',
    );

    expect(config.instructions, <String>[
      'AGENTS.md',
      'docs/*.md',
      'https://example.com/a.md',
    ]);
  });

  test('instructions 类型非法抛 ConfigException', () {
    expect(
      () => _load('instructions = "AGENTS.md"'),
      throwsA(isA<ConfigException>()),
    );
  });
}

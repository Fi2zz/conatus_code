/// 顶层 `bootstrap_skills`：启动时强制注入的技能名列表。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

ConatusCodeConfig _load(String toml) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-bootstrap');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String path = '${dir.path}${Platform.pathSeparator}$kConfigFileName';
  File(path).writeAsStringSync(toml);
  return loadConfig(path: path);
}

void main() {
  test('bootstrap_skills 缺省为空', () {
    expect(_load('').bootstrapSkills, isEmpty);
  });

  test('bootstrap_skills 按书写顺序解析并过滤空白', () {
    final ConatusCodeConfig config = _load(
      'bootstrap_skills = ["using-superpowers", "", " other "]',
    );

    expect(config.bootstrapSkills, <String>['using-superpowers', 'other']);
  });

  test('bootstrap_skills 类型非法抛 ConfigException', () {
    expect(
      () => _load('bootstrap_skills = "using-superpowers"'),
      throwsA(isA<ConfigException>()),
    );
  });
}

/// `[story]` 配置解析：缺省关闭、显式开启、非法类型 fail-closed。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-story-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File(
    '${dir.path}${Platform.pathSeparator}$kConfigFileName',
  );
  file.writeAsStringSync(content);
  return file.path;
}

ConatusCodeConfig _load(String toml) => loadConfig(path: _writeToml(toml));

void main() {
  test('[story] 缺省：enabled 为 false', () {
    expect(_load('[story]\n').story.enabled, isFalse);
  });

  test('[story] enabled = true 被读取', () {
    expect(_load('[story]\nenabled = true\n').story.enabled, isTrue);
  });

  test('[story] enabled 非法类型抛 ConfigException', () {
    expect(
      () => _load('[story]\nenabled = "yes"\n'),
      throwsA(isA<ConfigException>()),
    );
  });

  test('首次启动写入的模板包含 [story] 说明', () {
    final Directory dir = Directory.systemTemp.createTempSync('nava-story-tpl');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String path = '${dir.path}${Platform.pathSeparator}$kConfigFileName';
    loadConfig(path: path);
    final String template = File(path).readAsStringSync();
    expect(template, contains('# [story]'));
    expect(template, contains('enabled = true'));
  });
}

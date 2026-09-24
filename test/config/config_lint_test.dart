/// `[lint]` 表解析测试。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-lint-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}${Platform.pathSeparator}$kConfigFileName');
  file.writeAsStringSync(content);
  return file.path;
}

void main() {
  test('缺省：enabled true / debounce 10 / command null', () {
    final ConatusCodeConfig config = loadConfig(path: _writeToml('[agent]\n'));
    expect(config.lint.enabled, isTrue);
    expect(config.lint.debounceSeconds, 10);
    expect(config.lint.command, isNull);
  });

  test('完整解析', () {
    final ConatusCodeConfig config = loadConfig(path: _writeToml('''
[lint]
enabled = false
command = "dart analyze"
debounce_seconds = 30
'''));
    expect(config.lint.enabled, isFalse);
    expect(config.lint.command, 'dart analyze');
    expect(config.lint.debounceSeconds, 30);
  });

  test('debounce_seconds 为负抛 ConfigException', () {
    expect(
      () => loadConfig(path: _writeToml('[lint]\ndebounce_seconds = -1\n')),
      throwsA(isA<ConfigException>()),
    );
  });
}

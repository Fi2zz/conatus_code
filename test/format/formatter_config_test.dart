/// `[formatter]` 表解析：缺省关闭、表存在默认开启、字段与非法值。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-format-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File(
    '${dir.path}${Platform.pathSeparator}$kConfigFileName',
  );
  file.writeAsStringSync(content);
  return file.path;
}

void main() {
  test('缺省：无 [formatter] 表 → enabled false（零行为变化）', () {
    final ConatusCodeConfig config = loadConfig(path: _writeToml('[agent]\n'));
    expect(config.formatter.enabled, isFalse);
    expect(config.formatter.command, isNull);
    expect(config.formatter.timeoutMs, 10000);
    expect(config.formatter.extensions, isEmpty);
  });

  test('[formatter] 表存在但未写 enabled → 默认开启', () {
    final ConatusCodeConfig config = loadConfig(
      path: _writeToml('[formatter]\n'),
    );
    expect(config.formatter.enabled, isTrue);
  });

  test('完整解析', () {
    final ConatusCodeConfig config = loadConfig(
      path: _writeToml('''
[formatter]
enabled = true
command = 'prettier --write \$FILE'
timeout_ms = 5000
extensions = [".ts", ".tsx"]
'''),
    );
    expect(config.formatter.enabled, isTrue);
    expect(config.formatter.command, r'prettier --write $FILE');
    expect(config.formatter.timeoutMs, 5000);
    expect(config.formatter.extensions, <String>['.ts', '.tsx']);
  });

  test('enabled=false 显式关闭', () {
    final ConatusCodeConfig config = loadConfig(
      path: _writeToml('[formatter]\nenabled = false\n'),
    );
    expect(config.formatter.enabled, isFalse);
  });

  test('timeout_ms 非正 → ConfigException', () {
    expect(
      () => loadConfig(path: _writeToml('[formatter]\ntimeout_ms = 0\n')),
      throwsA(isA<ConfigException>()),
    );
  });
}

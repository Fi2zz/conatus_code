/// `[xerj]` 表解析测试。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-xerj-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File(
    '${dir.path}${Platform.pathSeparator}$kConfigFileName',
  );
  file.writeAsStringSync(content);
  return file.path;
}

ConatusCodeConfig _load(String toml) => loadConfig(path: _writeToml(toml));

void main() {
  test('缺省：enabled true / 本地 19200 / 数据目录与前缀留空', () {
    final ConatusCodeConfig config = _load('[agent]\nmax_steps = 8\n');

    expect(config.xerj.enabled, isTrue);
    expect(config.xerj.url, 'http://127.0.0.1:19200');
    expect(config.xerj.dataDir, isNull);
    expect(config.xerj.prefix, isNull);
  });

  test('完整解析', () {
    final ConatusCodeConfig config = _load('''
[xerj]
enabled = false
url = "http://127.0.0.1:19300"
data_dir = "~/xerj-data"
prefix = "nava-fixed"
''');

    expect(config.xerj.enabled, isFalse);
    expect(config.xerj.url, 'http://127.0.0.1:19300');
    expect(config.xerj.dataDir, '~/xerj-data');
    expect(config.xerj.prefix, 'nava-fixed');
  });

  test('enabled 非布尔抛 ConfigException', () {
    expect(
      () => _load('[xerj]\nenabled = "yes"\n'),
      throwsA(isA<ConfigException>()),
    );
  });
}

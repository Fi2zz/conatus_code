/// 沙箱开关：`[sandbox] enabled` 的解析与缺省值。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir =
      Directory.systemTemp.createTempSync('conatus-sandbox-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

String _writeConfig(String content) {
  final File file =
      File('${_tempDir().path}${Platform.pathSeparator}$kConfigFileName');
  file.writeAsStringSync(content);
  return file.path;
}

void main() {
  test('sandbox.enabled：显式 true 生效，缺省 false', () {
    final ConatusCodeConfig enabled = loadConfig(
        path: _writeConfig('[sandbox]\nenabled = true\n'));
    expect(enabled.sandbox.enabled, isTrue);

    final ConatusCodeConfig defaulted = loadConfig(
        path: _writeConfig('[sandbox]\nallow_network = true\n'));
    expect(defaulted.sandbox.enabled, isFalse);
  });
}

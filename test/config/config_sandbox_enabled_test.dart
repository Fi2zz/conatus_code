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
  test('sandbox.enabled：显式 false 生效，缺省 true', () {
    final ConatusCodeConfig disabled = loadConfig(
        path: _writeConfig('[sandbox]\nenabled = false\n'));
    expect(disabled.sandbox.enabled, isFalse);

    final ConatusCodeConfig defaulted = loadConfig(
        path: _writeConfig('[sandbox]\nallow_network = true\n'));
    expect(defaulted.sandbox.enabled, isTrue);
  });

  test('sandbox.fs_jail：显式 false 生效，缺省 true（与 enabled 独立）', () {
    final ConatusCodeConfig noJail = loadConfig(
        path: _writeConfig('[sandbox]\nfs_jail = false\n'));
    expect(noJail.sandbox.fsJail, isFalse);
    expect(noJail.sandbox.enabled, isTrue);

    final ConatusCodeConfig defaulted =
        loadConfig(path: _writeConfig('[sandbox]\nenabled = false\n'));
    expect(defaulted.sandbox.fsJail, isTrue);
  });
}

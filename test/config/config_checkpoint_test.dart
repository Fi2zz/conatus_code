/// `[checkpoint]` 表解析测试。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-cp-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File(
    '${dir.path}${Platform.pathSeparator}$kConfigFileName',
  );
  file.writeAsStringSync(content);
  return file.path;
}

ConatusCodeConfig _load(String toml) => loadConfig(path: _writeToml(toml));

void main() {
  test('缺省值：enabled true / keep 5 / ignore 空 / backend auto', () {
    final ConatusCodeConfig config = _load('[agent]\nmax_steps = 8\n');
    expect(config.checkpoint.enabled, isTrue);
    expect(config.checkpoint.keep, 5);
    expect(config.checkpoint.ignore, isEmpty);
    expect(config.checkpoint.backend, CheckpointBackend.auto);
  });

  test('完整解析', () {
    final ConatusCodeConfig config = _load('''
[checkpoint]
enabled = false
keep = 0
ignore = ["node_modules", "build/"]
backend = "archive"
''');
    expect(config.checkpoint.enabled, isFalse);
    expect(config.checkpoint.keep, 0);
    expect(config.checkpoint.ignore, <String>['node_modules', 'build/']);
    expect(config.checkpoint.backend, CheckpointBackend.archive);
  });

  test('backend = "git"', () {
    final ConatusCodeConfig config = _load('[checkpoint]\nbackend = "git"\n');
    expect(config.checkpoint.backend, CheckpointBackend.git);
  });

  test('backend 拼错回落到 auto（不让检查点整个失效）', () {
    // 值层容错：引号里写了不认识的后端，按 auto 走（快照继续可用）。
    for (final String raw in <String>['"shadow"', '"GIT"', '""']) {
      final ConatusCodeConfig config = _load('[checkpoint]\nbackend = $raw\n');
      expect(config.checkpoint.backend, CheckpointBackend.auto, reason: raw);
    }
  });

  test('backend 未加引号是 TOML 语法错，照常抛（与 enabled 一致）', () {
    expect(
      () => _load('[checkpoint]\nbackend = shadow\n'),
      throwsA(isA<ConfigException>()),
    );
  });

  test('keep 为负抛 ConfigException', () {
    expect(
      () => _load('[checkpoint]\nkeep = -1\n'),
      throwsA(isA<ConfigException>()),
    );
  });

  test('enabled 非布尔抛 ConfigException', () {
    expect(
      () => _load('[checkpoint]\nenabled = "yes"\n'),
      throwsA(isA<ConfigException>()),
    );
  });
}

/// checkpoint 恢复侧符号链接防护：文件链接不穿透、父目录链接 fail-closed。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

/// 建临时工作区与 store，返回 (store, root, projectDir)。
(CheckpointStore, String, String) _store() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-cp-esc');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String root = '${dir.path}${Platform.pathSeparator}ws';
  final String projectDir = '$root${Platform.pathSeparator}.conatus';
  Directory(projectDir).createSync(recursive: true);
  return (
    CheckpointStore(root: root, projectDir: projectDir),
    root,
    projectDir,
  );
}

void _write(String root, String rel, String content) {
  final File file = File('$root${Platform.pathSeparator}$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

void main() {
  test('rewind 不穿透文件符号链接覆写工作区外文件', () async {
    if (Platform.isWindows) return; // symlink 需权限
    final (CheckpointStore store, String root, _) = _store();
    final Directory outside = Directory.systemTemp.createTempSync(
      'nava-cp-ext',
    );
    addTearDown(() => outside.deleteSync(recursive: true));
    final String external =
        '${outside.path}${Platform.pathSeparator}external.txt';
    File(external).writeAsStringSync('外部原文');

    _write(root, 'a.txt', 'v0');
    await store.snapshot('s', 0);
    File('$root${Platform.pathSeparator}a.txt').deleteSync();
    Link('$root${Platform.pathSeparator}a.txt').createSync(external);

    await restoreCheckpoint(store, 's', 0);

    expect(File(external).readAsStringSync(), '外部原文');
    final String restored = '$root${Platform.pathSeparator}a.txt';
    expect(
      FileSystemEntity.typeSync(restored, followLinks: false),
      FileSystemEntityType.file,
    );
    expect(File(restored).readAsStringSync(), 'v0');
  });

  test('rewind 父目录为外部 symlink 时 fail-closed 且工作区不动', () async {
    if (Platform.isWindows) return;
    final (CheckpointStore store, String root, _) = _store();
    final Directory outside = Directory.systemTemp.createTempSync(
      'nava-cp-ext',
    );
    addTearDown(() => outside.deleteSync(recursive: true));
    _write(outside.path, 'b.txt', '外部原文');

    _write(root, 'sub/b.txt', 'v0');
    await store.snapshot('s', 0);
    Directory('$root${Platform.pathSeparator}sub').deleteSync(recursive: true);
    Link('$root${Platform.pathSeparator}sub').createSync(outside.path);

    await expectLater(
      restoreCheckpoint(store, 's', 0),
      throwsA(
        isA<CheckpointException>().having(
          (CheckpointException e) => e.code,
          'code',
          'restore-escape',
        ),
      ),
    );
    expect(
      File('${outside.path}${Platform.pathSeparator}b.txt').readAsStringSync(),
      '外部原文',
    );
  });
}

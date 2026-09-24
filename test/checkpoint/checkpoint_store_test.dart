/// CheckpointStore（delta 版）：base 全量 + 差量、prune、list、旧格式兼容。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

/// 建临时「工作区 + 项目数据目录」，返回 (store, root, projectDir)。
(CheckpointStore, String, String) _setup({
  int keep = 5,
  List<String> ignore = const <String>[],
}) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-cp-store');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String root = dir.path;
  final String projectDir = '$root${Platform.pathSeparator}.conatus';
  Directory(projectDir).createSync();
  return (
    CheckpointStore(root: root, projectDir: projectDir, keep: keep, ignore: ignore),
    root,
    projectDir,
  );
}

void _write(String root, String rel, String content) {
  final File file = File('$root${Platform.pathSeparator}$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

/// 强制文件的 mtime/size 变化（写不同内容即可触发 delta 复制）。
void _touch(String root, String rel, String content) =>
    _write(root, rel, content);

void main() {
  test('turn 0 全量 base（含 mtime/size），跳过排除项，写 manifest', () async {
    final (CheckpointStore store, String root, String projectDir) = _setup(
      ignore: const <String>['node_modules'],
    );
    _write(root, 'lib/main.dart', 'void main() {}');
    _write(root, 'README.md', '# hi');
    _write(root, '.git/config', 'not-snapshotted');
    _write(root, 'node_modules/pkg/index.js', 'skip');
    _write(root, '.conatus/secret.json', 'skip');

    await store.snapshot('s1', 0, lastEventId: 'ev-0');

    final List<CheckpointInfo> infos = store.list('s1');
    expect(infos.single.turn, 0);
    expect(infos.single.files, 2);
    final CheckpointManifest base = store.manifestOf('s1', 0);
    expect(base.isDelta, isFalse);
    expect(base.lastEventId, 'ev-0');
    expect(
      base.files.map((CheckpointFileEntry e) => e.path),
      unorderedEquals(<String>['lib/main.dart', 'README.md']),
    );
    expect(base.files.every((CheckpointFileEntry e) => e.size > 0), isTrue);
  });

  test('turn 1 差量：只存变化/新增文件，deleted 记录删除', () async {
    final (CheckpointStore store, String root, String projectDir) = _setup();
    _write(root, 'a.txt', 'v0');
    _write(root, 'b.txt', 'b0');
    await store.snapshot('s1', 0);

    _touch(root, 'a.txt', 'v1'); // 变化
    _write(root, 'c.txt', 'new'); // 新增
    File('$root${Platform.pathSeparator}b.txt').deleteSync(); // 删除
    await store.snapshot('s1', 1, lastEventId: 'ev-1');

    final CheckpointManifest delta = store.manifestOf('s1', 1);
    expect(delta.isDelta, isTrue);
    expect(delta.changed, unorderedEquals(<String>['a.txt', 'c.txt']));
    expect(delta.deleted, <String>['b.txt']);
    // 每个检查点是单个归档文件（1.gz），内容压缩非明文。
    final String turnDir = '$projectDir${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}s1';
    expect(File('$turnDir${Platform.pathSeparator}1.gz').existsSync(), isTrue);
    expect(File('$turnDir${Platform.pathSeparator}0.gz').existsSync(), isTrue);
    expect(
      Directory('$turnDir${Platform.pathSeparator}1').existsSync(),
      isFalse,
    );
    final List<int> raw =
        File('$turnDir${Platform.pathSeparator}1.gz').readAsBytesSync();
    expect(utf8.decode(raw, allowMalformed: true).contains('v1'), isFalse);
    // list 有效文件数 = base(2) + changed新增(1) - deleted(1) = 2。
    expect(store.list('s1').last.files, 2);
  });

  test('mtime+size 不变的文件不进差量（不重复复制）', () async {
    final (CheckpointStore store, String root, String projectDir) = _setup();
    _write(root, 'a.txt', 'same');
    await store.snapshot('s1', 0);
    await store.snapshot('s1', 1);

    final CheckpointManifest delta = store.manifestOf('s1', 1);
    expect(delta.changed, isEmpty);
    expect(delta.deleted, isEmpty);
  });

  test('prune 保留 base + 最近 keep-1 个差量；keep<=0 不裁剪', () async {
    final (CheckpointStore store, String root, String projectDir) =
        _setup(keep: 3);
    _write(root, 'a.txt', 'v0');
    await store.snapshot('s1', 0);
    for (int turn = 1; turn < 5; turn++) {
      _write(root, 'a.txt', 'v$turn');
      await store.snapshot('s1', turn);
    }
    expect(store.turnsOf('s1'), <int>[0, 3, 4]);

    final (CheckpointStore unlimited, _, _) = _setup(keep: 0);
    await unlimited.snapshot('s2', 0);
    for (int turn = 1; turn < 4; turn++) {
      await unlimited.snapshot('s2', turn);
    }
    expect(unlimited.turnsOf('s2'), <int>[0, 1, 2, 3]);
  });

  test('缺失检查点 / 缺失清单抛 CheckpointException', () async {
    final (CheckpointStore store, _, String projectDir) = _setup();
    expect(
      () => store.manifestOf('s1', 9),
      throwsA(isA<CheckpointException>()),
    );
    await store.snapshot('s1', 0);
    store.archiveFile('s1', 0).deleteSync();
    expect(
      () => store.manifestOf('s1', 0),
      throwsA(isA<CheckpointException>()),
    );
  });

  test('旧格式兼容：无 kind 的清单按 base 读（files 为字符串路径）', () {
    final (CheckpointStore store, _, String projectDir) = _setup();
    final String legacy = '$projectDir${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}s1${Platform.pathSeparator}0';
    Directory(legacy).createSync(recursive: true);
    File('$legacy${Platform.pathSeparator}manifest.json')
        .writeAsStringSync('{"turn":0,"files":["a.txt","b.txt"]}');

    final CheckpointManifest manifest = store.manifestOf('s1', 0);
    expect(manifest.isDelta, isFalse);
    expect(
      manifest.files.map((CheckpointFileEntry e) => e.path),
      unorderedEquals(<String>['a.txt', 'b.txt']),
    );
  });

  test('符号链接跳过；空工作区 base 清单为空', () async {
    final (CheckpointStore store, String root, String projectDir) = _setup();
    _write(root, 'a.txt', 'x');
    final Link link = Link('$root${Platform.pathSeparator}link.txt');
    link.createSync('$root${Platform.pathSeparator}a.txt');

    await store.snapshot('s1', 0);

    final CheckpointManifest base = store.manifestOf('s1', 0);
    expect(base.files.map((CheckpointFileEntry e) => e.path),
        <String>['a.txt']);

    final (CheckpointStore emptyStore, _, _) = _setup();
    await emptyStore.snapshot('s2', 0);
    expect(emptyStore.manifestOf('s2', 0).files, isEmpty);
  });
}

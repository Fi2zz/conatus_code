/// CheckpointStore（delta 版）：base 全量 + 差量、prune、list、旧格式兼容。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

/// 建临时「工作区 + 项目数据目录」，返回 (store, root, projectDir)。
(ArchiveCheckpointStore, String, String) _setup({
  int keep = 5,
  List<String> ignore = const <String>[],
}) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-cp-store');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String root = dir.path;
  final String projectDir = '$root${Platform.pathSeparator}.conatus';
  Directory(projectDir).createSync();
  return (
    ArchiveCheckpointStore(
      root: root,
      projectDir: projectDir,
      keep: keep,
      ignore: ignore,
    ),
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
    final (ArchiveCheckpointStore store, String root, String projectDir) =
        _setup(ignore: const <String>['node_modules']);
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
    final (ArchiveCheckpointStore store, String root, String projectDir) =
        _setup();
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
    // 归档文件名不可读（哈希名），无 `<轮次>` 可读目录/文件，内容非明文。
    final String turnDir =
        '$projectDir${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}s1';
    expect(store.archiveFile('s1', 0).existsSync(), isTrue);
    expect(store.archiveFile('s1', 1).existsSync(), isTrue);
    final List<String> names = Directory(turnDir)
        .listSync()
        .map((FileSystemEntity e) => e.path.split(Platform.pathSeparator).last)
        .toList();
    // 无可读轮次名、无扩展名（看不出是 gzip）。
    expect(
      names.any(
        (String n) => n == '0' || n == '1' || n == '0.gz' || n == '1.gz',
      ),
      isFalse,
    );
    expect(names.any((String n) => n.endsWith('.gz')), isFalse);
    expect(names, contains('index'));
    final List<int> raw = store.archiveFile('s1', 1).readAsBytesSync();
    expect(utf8.decode(raw, allowMalformed: true).contains('v1'), isFalse);
    // list 有效文件数 = base(2) + changed新增(1) - deleted(1) = 2。
    expect(store.list('s1').last.files, 2);
  });

  test('mtime+size 不变的文件不进差量（不重复复制）', () async {
    final (ArchiveCheckpointStore store, String root, String projectDir) =
        _setup();
    _write(root, 'a.txt', 'same');
    await store.snapshot('s1', 0);
    await store.snapshot('s1', 1);

    final CheckpointManifest delta = store.manifestOf('s1', 1);
    expect(delta.changed, isEmpty);
    expect(delta.deleted, isEmpty);
  });

  test('prune 保留 base + 最近 keep-1 个差量；keep<=0 不裁剪', () async {
    final (ArchiveCheckpointStore store, String root, String projectDir) =
        _setup(keep: 3);
    _write(root, 'a.txt', 'v0');
    await store.snapshot('s1', 0);
    for (int turn = 1; turn < 5; turn++) {
      _write(root, 'a.txt', 'v$turn');
      await store.snapshot('s1', turn);
    }
    expect(store.turnsOf('s1'), <int>[0, 3, 4]);

    final (ArchiveCheckpointStore unlimited, _, _) = _setup(keep: 0);
    await unlimited.snapshot('s2', 0);
    for (int turn = 1; turn < 4; turn++) {
      await unlimited.snapshot('s2', turn);
    }
    expect(unlimited.turnsOf('s2'), <int>[0, 1, 2, 3]);
  });

  test('缺失检查点 / 缺失清单抛 CheckpointException', () async {
    final (ArchiveCheckpointStore store, _, String projectDir) = _setup();
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
    final (ArchiveCheckpointStore store, _, String projectDir) = _setup();
    final String legacy =
        '$projectDir${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}s1${Platform.pathSeparator}0';
    Directory(legacy).createSync(recursive: true);
    File(
      '$legacy${Platform.pathSeparator}manifest.json',
    ).writeAsStringSync('{"turn":0,"files":["a.txt","b.txt"]}');

    final CheckpointManifest manifest = store.manifestOf('s1', 0);
    expect(manifest.isDelta, isFalse);
    expect(
      manifest.files.map((CheckpointFileEntry e) => e.path),
      unorderedEquals(<String>['a.txt', 'b.txt']),
    );
  });

  test('符号链接跳过；空工作区 base 清单为空', () async {
    final (ArchiveCheckpointStore store, String root, String projectDir) =
        _setup();
    _write(root, 'a.txt', 'x');
    final Link link = Link('$root${Platform.pathSeparator}link.txt');
    link.createSync('$root${Platform.pathSeparator}a.txt');

    await store.snapshot('s1', 0);

    final CheckpointManifest base = store.manifestOf('s1', 0);
    expect(base.files.map((CheckpointFileEntry e) => e.path), <String>[
      'a.txt',
    ]);

    final (ArchiveCheckpointStore emptyStore, _, _) = _setup();
    await emptyStore.snapshot('s2', 0);
    expect(emptyStore.manifestOf('s2', 0).files, isEmpty);
  });

  test('readFile 读 base 与差量内容；删除/缺失/只读路径返回 null', () async {
    final (ArchiveCheckpointStore store, String root, _) = _setup();
    _write(root, 'a.txt', 'v0');
    _write(root, 'b.txt', 'b0');
    await store.snapshot('s1', 0);

    _write(root, 'a.txt', 'v1');
    _write(root, 'c.txt', 'c1');
    File('$root${Platform.pathSeparator}b.txt').deleteSync();
    await store.snapshot('s1', 1);

    expect(utf8.decode((await store.readFile('s1', 0, 'a.txt'))!), 'v0');
    expect(utf8.decode((await store.readFile('s1', 1, 'a.txt'))!), 'v1');
    // 差量里没变的文件要回落到 base（diff 的两侧都得有内容）。
    expect(utf8.decode((await store.readFile('s1', 1, 'c.txt'))!), 'c1');
    // 该轮已删除 / 从未存在 / 轮次不存在：null。
    expect(await store.readFile('s1', 1, 'b.txt'), isNull);
    expect(await store.readFile('s1', 0, 'c.txt'), isNull);
    expect(await store.readFile('s1', 9, 'a.txt'), isNull);
    // 只读 / 越界路径一律 null。
    _write(root, '.opencode/config.json', '{}');
    expect(await store.readFile('s1', 1, '.opencode/config.json'), isNull);
    expect(await store.readFile('s1', 1, '.OPENCODE/config.json'), isNull);
    expect(await store.readFile('s1', 1, '../outside.txt'), isNull);
  });

  test('changesBetween：added/modified/deleted；同轮为空；反向对称', () async {
    final (ArchiveCheckpointStore store, String root, _) = _setup();
    _write(root, 'mod.txt', 'm0');
    _write(root, 'del.txt', 'd0');
    _write(root, 'same.txt', 's0');
    await store.snapshot('s1', 0);

    _write(root, 'mod.txt', 'm1');
    File('$root${Platform.pathSeparator}del.txt').deleteSync();
    _write(root, 'add.txt', 'a1');
    await store.snapshot('s1', 1);

    final Map<String, String> forward = _summary(
      await store.changesBetween('s1', 0, 1),
    );
    expect(forward, <String, String>{
      'mod.txt': 'modified',
      'del.txt': 'deleted',
      'add.txt': 'added',
    });
    expect(await store.changesBetween('s1', 1, 1), isEmpty);
    expect(_summary(await store.changesBetween('s1', 1, 0)), <String, String>{
      'mod.txt': 'modified',
      'del.txt': 'added',
      'add.txt': 'deleted',
    });
  });

  test('changesBetween 跨多轮：只报真正变化的文件（内容比对兜底）', () async {
    final (ArchiveCheckpointStore store, String root, _) = _setup();
    _write(root, 'mod.txt', 'm0');
    await store.snapshot('s1', 0);
    _write(root, 'mod.txt', 'm1');
    _write(root, 'add.txt', 'a1'); // 两轮之间不变
    await store.snapshot('s1', 1);
    _write(root, 'mod.txt', 'm2');
    await store.snapshot('s1', 2);

    final Map<String, String> changes = _summary(
      await store.changesBetween('s1', 1, 2),
    );
    expect(changes, <String, String>{
      'mod.txt': 'modified',
    }, reason: 'add.txt 在两轮里都相对 base 变化，但轮间内容相同，不算变化');
  });

  test('changesBetween / readFile 过滤只读路径（大小写不敏感）', () async {
    final (ArchiveCheckpointStore store, String root, _) = _setup();
    _write(root, 'a.txt', 'v0');
    await store.snapshot('s1', 0);
    // 手工造一个含 .opencode 的旧归档：采集侧现在会排除它，故直接写归档；
    // 删掉索引让 list() 按归档头部重建。
    await writeCheckpointArchive(
      store.archiveFile('s1', 2),
      const CheckpointManifest(
        kind: 'delta',
        turn: 2,
        changed: <String>['a.txt', '.opencode/x', '.OPENCODE/y'],
      ),
      <CheckpointArchiveEntry>[
        ('a.txt', utf8.encode('v2')),
        ('.opencode/x', utf8.encode('x')),
        ('.OPENCODE/y', utf8.encode('y')),
      ],
    );
    store.indexFile('s1').deleteSync();

    final List<CheckpointFileChange> changes = await store.changesBetween(
      's1',
      0,
      2,
    );
    expect(changes.map((CheckpointFileChange c) => c.path), <String>['a.txt']);
    // 归档里**确实有**这两个条目，仍须一律读不到（不是「碰巧不存在」）。
    expect(await store.readFile('s1', 2, '.opencode/x'), isNull);
    expect(
      await store.readFile('s1', 2, '.OPENCODE/y'),
      isNull,
      reason: 'APFS / NTFS 上 .OPENCODE 就是 .opencode',
    );
  });

  test('changesBetween 轮次不存在抛 missing-checkpoint（与 git 后端同码）', () async {
    final (ArchiveCheckpointStore store, String root, _) = _setup();
    _write(root, 'a.txt', 'v0');
    await store.snapshot('s1', 0);

    await expectLater(
      store.changesBetween('s1', 0, 7),
      throwsA(
        isA<CheckpointException>().having(
          (CheckpointException e) => e.code,
          'code',
          'missing-checkpoint',
        ),
      ),
    );
  });

  test('turn 的归档缺失：readFile 返回 null，changesBetween 报错', () async {
    final (ArchiveCheckpointStore store, String root, _) = _setup();
    _write(root, 'a.txt', 'v0');
    await store.snapshot('s1', 0);
    _write(root, 'a.txt', 'v1');
    await store.snapshot('s1', 1);
    // 索引还记着 turn 1，但归档被删（磁盘损坏 / 手工清理）。
    store.archiveFile('s1', 1).deleteSync();

    expect(await store.readFile('s1', 1, 'a.txt'), isNull);
    await expectLater(
      store.changesBetween('s1', 0, 1),
      throwsA(
        isA<CheckpointException>().having(
          (CheckpointException e) => e.code,
          'code',
          'missing-checkpoint',
        ),
      ),
      reason: '不能退回 base 内容把「差量丢了」伪装成「文件没变」',
    );
  });

  test('workdir 为 \$HOME 时全局 .config/opencode 不进快照', () async {
    final String sep = Platform.pathSeparator;
    expect(
      checkpointExcluded(
        '.config${sep}opencode${sep}config.json',
        '.conatus',
        const <String>[],
      ),
      isTrue,
    );
    expect(
      checkpointExcluded(
        '.config${sep}other${sep}x.json',
        '.conatus',
        const <String>[],
      ),
      isFalse,
    );
  });
}

/// `path → status` 摘要（断言用）。
Map<String, String> _summary(
  List<CheckpointFileChange> changes,
) => <String, String>{
  for (final CheckpointFileChange change in changes) change.path: change.status,
};

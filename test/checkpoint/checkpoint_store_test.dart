/// CheckpointStore：快照 / 恢复 / prune / 清单 / 排除项（真实临时目录）。
library;

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

/// 在 [root] 下写文件；[content] 为 null 表示删除。
void _write(String root, String rel, String? content) {
  final File file = File('$root${Platform.pathSeparator}$rel');
  if (content == null) {
    if (file.existsSync()) file.deleteSync();
    return;
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

String _read(String root, String rel) =>
    File('$root${Platform.pathSeparator}$rel').readAsStringSync();

bool _exists(String root, String rel) =>
    File('$root${Platform.pathSeparator}$rel').existsSync();

void main() {
  test('快照复制文件、跳过 .git/.conatus/ignore/符号链接，写 manifest', () async {
    final (CheckpointStore store, String root, String projectDir) = _setup(
      ignore: const <String>['node_modules'],
    );
    _write(root, 'lib/main.dart', 'void main() {}');
    _write(root, 'README.md', '# hi');
    _write(root, '.git/config', 'not-snapshotted');
    _write(root, 'node_modules/pkg/index.js', 'skip');
    _write(root, '.conatus/secret.json', 'skip');
    final Link link = Link('$root${Platform.pathSeparator}link.dart');
    link.createSync('lib/main.dart');

    await store.snapshot('s1', 1, lastEventId: 'ev-99');

    final List<int> turns = store.list('s1');
    expect(turns, <int>[1]);
    final CheckpointManifest manifest = store.manifestOf('s1', 1);
    expect(
      manifest.files,
      unorderedEquals(<String>['lib/main.dart', 'README.md']),
    );
    expect(manifest.lastEventId, 'ev-99');
    final String cpDir = '$projectDir${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}s1${Platform.pathSeparator}1';
    expect(File('$cpDir${Platform.pathSeparator}lib/main.dart').existsSync(), isTrue);
    expect(
        File('$cpDir${Platform.pathSeparator}.git/config').existsSync(), isFalse);
    expect(
        File('$cpDir${Platform.pathSeparator}node_modules/pkg/index.js')
            .existsSync(),
        isFalse);
  });

  test('恢复：覆盖被改文件、删除新增文件、补回被删文件', () async {
    final (CheckpointStore store, String root, String projectDir) = _setup();
    _write(root, 'a.txt', 'v1');
    _write(root, 'b.txt', 'b1');
    await store.snapshot('s1', 1);

    // 模型改乱了：a 被改、b 被删、c 是新增。
    _write(root, 'a.txt', 'v2-broken');
    _write(root, 'b.txt', null);
    _write(root, 'c.txt', 'extra');

    final CheckpointRestore result = await store.restore('s1', 1);

    expect(result.restored, 2); // a.txt 覆盖 + b.txt 补回
    expect(result.deleted, 1); // c.txt 删除
    expect(_read(root, 'a.txt'), 'v1');
    expect(_read(root, 'b.txt'), 'b1');
    expect(_exists(root, 'c.txt'), isFalse);
  });

  test('prune 保留最近 keep 个；keep<=0 不裁剪', () async {
    final (CheckpointStore store, String root, String projectDir) =
        _setup(keep: 2);
    for (int turn = 0; turn < 5; turn++) {
      _write(root, 'f$turn.txt', 'x');
      await store.snapshot('s1', turn);
    }
    expect(store.list('s1'), <int>[3, 4]);

    final (CheckpointStore unlimited, _, _) = _setup(keep: 0);
    for (int turn = 0; turn < 3; turn++) {
      await unlimited.snapshot('s2', turn);
    }
    expect(unlimited.list('s2'), <int>[0, 1, 2]);
  });

  test('缺失检查点 / 缺失清单抛 CheckpointException', () async {
    final (CheckpointStore store, _, String projectDir) = _setup();
    expect(
      () => store.restore('s1', 9),
      throwsA(isA<CheckpointException>()),
    );
    await store.snapshot('s1', 0);
    File(
        '$projectDir${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}s1${Platform.pathSeparator}0'
        '${Platform.pathSeparator}manifest.json').deleteSync();
    expect(
      () => store.manifestOf('s1', 0),
      throwsA(isA<CheckpointException>()),
    );
  });

  test('空工作区快照：清单为空，恢复计数为 0，lastEventId 缺省为 null', () async {
    final (CheckpointStore store, String root, String projectDir) = _setup();
    await store.snapshot('s1', 0);
    final CheckpointManifest manifest = store.manifestOf('s1', 0);
    expect(manifest.files, isEmpty);
    expect(manifest.lastEventId, isNull);
    final CheckpointRestore result = await store.restore('s1', 0);
    expect(result.restored, 0);
    expect(result.deleted, 0);
  });

  test('恢复不触碰排除项（.git / .conatus）', () async {
    final (CheckpointStore store, String root, String projectDir) = _setup();
    _write(root, 'a.txt', 'v1');
    _write(root, '.git/config', 'git-state');
    await store.snapshot('s1', 1);

    _write(root, 'a.txt', 'v2');
    _write(root, '.git/config', 'new-git-state');
    _write(root, '.conatus/new.json', 'new-data');

    await store.restore('s1', 1);

    expect(_read(root, 'a.txt'), 'v1');
    expect(_read(root, '.git/config'), 'new-git-state'); // 不动
    expect(_read(root, '.conatus/new.json'), 'new-data'); // 不动
  });
}

/// `/diff` 数据源：checkpoint 两轮差异与工作区 git 差异。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

/// 临时工作区 + archive 检查点管理器。
(CheckpointManager, String) _workspace() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-diff-src');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String root = dir.path;
  Directory('$root${Platform.pathSeparator}.conatus').createSync();
  final CheckpointManager manager = CheckpointManager(
    store: ArchiveCheckpointStore(
      root: root,
      projectDir: '$root${Platform.pathSeparator}.conatus',
    ),
    config: const CheckpointConfig(),
  );
  return (manager, root);
}

void _write(String root, String rel, String content) {
  final File file = File('$root${Platform.pathSeparator}$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

Future<void> _git(String root, List<String> args) async {
  final ProcessResult result = await Process.run(
    'git',
    args,
    workingDirectory: root,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')}: ${result.stderr}');
  }
}

void main() {
  test('turn compares the target turn with the previous one', () async {
    final (CheckpointManager manager, String root) = _workspace();
    _write(root, 'a.txt', 'v0\n');
    await manager.bind('s1');
    _write(root, 'a.txt', 'v1\n');
    _write(root, 'b.txt', 'new\n');
    await manager.recordTurn(); // turn 1

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 1,
    ).load(DiffScope.turn);

    expect(diffs.map((FileDiff d) => d.path), <String>['a.txt', 'b.txt']);
    final FileDiff modified = diffs.first;
    expect(modified.status, 'modified');
    expect(modified.additions, 1);
    expect(modified.deletions, 1);
    expect(modified.hunks, isNotEmpty);
    final FileDiff added = diffs.last;
    expect(added.status, 'added');
    expect(added.additions, 1);
  });

  test('turn 0 compares the snapshot against empty', () async {
    final (CheckpointManager manager, String root) = _workspace();
    _write(root, 'a.txt', 'hello\n');
    await manager.bind('s1');

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 0,
    ).load(DiffScope.turn);

    expect(diffs.single.path, 'a.txt');
    expect(diffs.single.status, 'added');
    expect(diffs.single.hunks, isNotEmpty);
  });

  test('turn excludes .opencode paths captured by the filter', () async {
    final (CheckpointManager manager, String root) = _workspace();
    _write(root, '.opencode/config.json', 'v0\n');
    _write(root, 'a.txt', 'v0\n');
    await manager.bind('s1');
    _write(root, '.opencode/config.json', 'v1\n');
    _write(root, 'a.txt', 'v1\n');
    await manager.recordTurn();

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 1,
    ).load(DiffScope.turn);

    expect(diffs.map((FileDiff d) => d.path), <String>['a.txt']);
    expect(diffs.any((FileDiff d) => d.path.startsWith('.opencode')), isFalse);
  });

  test('working reports tracked changes and untracked files', () async {
    final (CheckpointManager manager, String root) = _workspace();
    await _git(root, <String>['init', '-q']);
    await _git(root, <String>['config', 'user.email', 't@example.com']);
    await _git(root, <String>['config', 'user.name', 'T']);
    _write(root, 'tracked.txt', 'one\n');
    await _git(root, <String>['add', '.']);
    await _git(root, <String>['commit', '-qm', 'init']);
    _write(root, 'tracked.txt', 'two\n');
    _write(root, 'untracked.txt', 'fresh\n');

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 0,
    ).load(DiffScope.working);

    final Map<String, FileDiff> byPath = <String, FileDiff>{
      for (final FileDiff diff in diffs) diff.path: diff,
    };
    expect(byPath['tracked.txt']?.status, 'modified');
    expect(byPath['tracked.txt']?.additions, 1);
    expect(byPath['untracked.txt']?.status, 'added');
    expect(byPath['untracked.txt']?.additions, 1);
  });

  test('working falls back to turn outside a git repository', () async {
    final (CheckpointManager manager, String root) = _workspace();
    _write(root, 'a.txt', 'v0\n');
    await manager.bind('s1');
    _write(root, 'a.txt', 'v1\n');
    await manager.recordTurn();

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 1,
    ).load(DiffScope.working);

    expect(diffs.single.path, 'a.txt');
    expect(diffs.single.status, 'modified');
  });
}

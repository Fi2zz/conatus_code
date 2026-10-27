/// SQLite 项目注册表：schema、读写、重命名与损坏兜底。
library;

import 'dart:io';

import 'package:conatus_code/src/project/project_database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-project-db');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

String _dbPath(Directory dir) => '${dir.path}/projects.db';

void main() {
  test('打开缺失的 DB 建表并写 user_version', () {
    final Directory dir = _tempDir();
    final String path = _dbPath(dir);
    final ProjectDatabase db = ProjectDatabase.open(path);
    addTearDown(db.close);

    expect(File(path).existsSync(), isTrue);
    final Database raw = sqlite3.open(path);
    addTearDown(raw.dispose);
    expect(raw.select('PRAGMA user_version').first.values.first, 1);
    expect(
      raw
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((Row row) => row['name'])
          .toSet(),
      containsAll(<String>['project', 'worktree']),
    );
  });

  test('项目与 worktree 读写往返', () {
    final ProjectDatabase db = ProjectDatabase.open(_dbPath(_tempDir()));
    addTearDown(db.close);

    db.saveProject(
      id: 'p1',
      name: 'lifts',
      vcs: 'git',
      remote: 'github.com/acme/lifts',
    );
    db.saveWorktree(
      id: 'w1',
      projectId: 'p1',
      path: '/tmp/lifts',
      name: 'lifts',
      dirName: 'lifts-3f9a2c1b7d4e',
    );

    expect(db.project('p1')!.name, 'lifts');
    expect(db.worktree('w1')!.path, '/tmp/lifts');
    expect(db.worktreeAt('/tmp/lifts')!.dirName, 'lifts-3f9a2c1b7d4e');
    expect(db.worktreeByDirName('lifts-3f9a2c1b7d4e')!.id, 'w1');
  });

  test('重复 path / dirName 仍是单行并更新字段', () {
    final ProjectDatabase db = ProjectDatabase.open(_dbPath(_tempDir()));
    addTearDown(db.close);
    db.saveProject(id: 'p1', name: 'lifts');
    db.saveWorktree(
      id: 'w1',
      projectId: 'p1',
      path: '/tmp/lifts',
      name: 'lifts',
      dirName: 'lifts-3f9a2c1b7d4e',
    );
    db.saveWorktree(
      id: 'w1',
      projectId: 'p1',
      path: '/tmp/lifts',
      name: 'lifts-renamed',
      dirName: 'lifts-3f9a2c1b7d4e',
    );

    expect(db.worktreeAt('/tmp/lifts')!.name, 'lifts-renamed');
    expect(db.worktreeByDirName('lifts-3f9a2c1b7d4e')!.id, 'w1');
  });

  test('renameProject 只改显示名，重新 saveProject 不覆盖', () {
    final ProjectDatabase db = ProjectDatabase.open(_dbPath(_tempDir()));
    addTearDown(db.close);
    db.saveProject(id: 'p1', name: 'lifts');
    db.renameProject('p1', 'Lifts 训练');
    db.saveProject(
      id: 'p1',
      name: 'ignored',
      vcs: 'git',
      remote: 'github.com/acme/lifts',
    );

    expect(db.project('p1')!.name, 'Lifts 训练');
    expect(db.project('p1')!.vcs, 'git');
  });

  test('transaction 成功提交、异常回滚', () {
    final ProjectDatabase db = ProjectDatabase.open(_dbPath(_tempDir()));
    addTearDown(db.close);

    db.transaction(() {
      db.saveProject(id: 'p1', name: 'lifts');
    });
    expect(db.project('p1'), isNotNull);

    expect(
      () => db.transaction(() {
        db.saveProject(id: 'p2', name: 'other');
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    expect(db.project('p2'), isNull);
  });

  test('数据库 / WAL / SHM 权限收紧到 0600', () {
    if (Platform.isWindows) return;
    final Directory dir = _tempDir();
    final String path = _dbPath(dir);
    final ProjectDatabase db = ProjectDatabase.open(path);
    addTearDown(db.close);
    db.saveProject(id: 'p1', name: 'lifts');

    for (final String suffix in <String>['', '-wal', '-shm']) {
      final File file = File('$path$suffix');
      expect(file.existsSync(), isTrue, reason: file.path);
      expect(
        file.statSync().mode & 0x1FF,
        0x180,
        reason: file.path,
      );
    }
  });

  test('重新打开保留记录', () {
    final String path = _dbPath(_tempDir());
    final ProjectDatabase first = ProjectDatabase.open(path);
    first.saveProject(id: 'p1', name: 'lifts');
    first.saveWorktree(
      id: 'w1',
      projectId: 'p1',
      path: '/tmp/lifts',
      name: 'lifts',
      dirName: 'lifts-3f9a2c1b7d4e',
    );
    first.close();

    final ProjectDatabase second = ProjectDatabase.open(path);
    addTearDown(second.close);
    expect(second.project('p1')!.name, 'lifts');
    expect(second.worktreeAt('/tmp/lifts')!.id, 'w1');
  });

  test('损坏的 DB 抛错并带路径', () {
    final Directory dir = _tempDir();
    final String path = '${dir.path}/broken.db';
    File(path).writeAsStringSync('not a database');

    expect(
      () => ProjectDatabase.open(path),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains(path),
        ),
      ),
    );
  });

  test('close 可重复调用', () {
    final ProjectDatabase db = ProjectDatabase.open(_dbPath(_tempDir()));
    db.close();
    db.close();
  });
}

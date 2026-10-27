/// SQLite 项目注册表：项目 / worktree 元数据与 schema 版本。
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// `project` 表的一行。
class ProjectRecord {
  const ProjectRecord({
    required this.id,
    required this.name,
    this.vcs,
    this.remote,
  });

  final String id;
  final String name;
  final String? vcs;
  final String? remote;
}

/// `worktree` 表的一行。
class WorktreeRecord {
  const WorktreeRecord({
    required this.id,
    required this.projectId,
    required this.path,
    required this.name,
    required this.dirName,
  });

  final String id;
  final String projectId;
  final String path;
  final String name;
  final String dirName;
}

/// 项目注册表数据库；同步 API，生命周期由调用方关闭。
class ProjectDatabase {
  ProjectDatabase._(this.path, this._db);

  /// 打开（必要时创建）数据库。
  factory ProjectDatabase.open(String path) {
    final Directory parent = File(path).parent;
    parent.createSync(recursive: true);
    Database db;
    try {
      db = sqlite3.open(path);
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA foreign_keys = ON');
      db.execute('PRAGMA busy_timeout = 5000');
      _migrate(db, path);
    } on SqliteException catch (error) {
      throw StateError('项目数据库无法打开或已损坏：$path（${error.message}）');
    } on StateError {
      rethrow;
    } catch (error) {
      throw StateError('项目数据库无法打开或已损坏：$path（$error）');
    }
    _restrictArtifacts(path);
    return ProjectDatabase._(path, db);
  }

  /// 数据库文件路径。
  final String path;
  final Database _db;
  bool _closed = false;

  ProjectRecord? project(String id) => _guard(() {
    final ResultSet rows = _db.select(
      'SELECT * FROM project WHERE id = ?',
      <Object?>[id],
    );
    return rows.isEmpty ? null : _projectFrom(rows.first);
  });

  WorktreeRecord? worktree(String id) => _guard(() {
    final ResultSet rows = _db.select(
      'SELECT * FROM worktree WHERE id = ?',
      <Object?>[id],
    );
    return rows.isEmpty ? null : _worktreeFrom(rows.first);
  });

  WorktreeRecord? worktreeAt(String worktreePath) => _guard(() {
    final ResultSet rows = _db.select(
      'SELECT * FROM worktree WHERE path = ?',
      <Object?>[worktreePath],
    );
    return rows.isEmpty ? null : _worktreeFrom(rows.first);
  });

  WorktreeRecord? worktreeByDirName(String dirName) => _guard(() {
    final ResultSet rows = _db.select(
      'SELECT * FROM worktree WHERE dir_name = ?',
      <Object?>[dirName],
    );
    return rows.isEmpty ? null : _worktreeFrom(rows.first);
  });

  void saveProject({
    required String id,
    required String name,
    String? vcs,
    String? remote,
  }) {
    _guard(() {
      final int now = DateTime.now().millisecondsSinceEpoch;
      _db.execute(
        '''
INSERT INTO project (id, name, vcs, remote, time_created, time_updated)
VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  vcs = excluded.vcs,
  remote = excluded.remote,
  time_updated = excluded.time_updated
''',
        <Object?>[id, name, vcs, remote, now, now],
      );
    });
  }

  void saveWorktree({
    required String id,
    required String projectId,
    required String path,
    required String name,
    required String dirName,
  }) {
    _guard(() {
      final int now = DateTime.now().millisecondsSinceEpoch;
      _db.execute(
        '''
INSERT INTO worktree
  (id, project_id, path, name, dir_name, time_created, time_updated)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  project_id = excluded.project_id,
  path = excluded.path,
  name = excluded.name,
  dir_name = excluded.dir_name,
  time_updated = excluded.time_updated
''',
        <Object?>[id, projectId, path, name, dirName, now, now],
      );
    });
  }

  void renameProject(String id, String name) {
    _guard(() {
      _db.execute(
        'UPDATE project SET name = ?, time_updated = ? WHERE id = ?',
        <Object?>[name, DateTime.now().millisecondsSinceEpoch, id],
      );
    });
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _db.dispose();
  }

  T _guard<T>(T Function() action) {
    try {
      return action();
    } on SqliteException catch (error) {
      throw StateError('项目数据库操作失败：$path（${error.message}）');
    }
  }

  static void _restrictArtifacts(String path) {
    if (Platform.isWindows) return;
    for (final String suffix in <String>['', '-wal', '-shm']) {
      final File file = File('$path$suffix');
      if (file.existsSync()) {
        Process.runSync('chmod', <String>['600', file.path]);
      }
    }
  }

  static void _migrate(Database db, String path) {
    final int version =
        db.select('PRAGMA user_version').first.values.first! as int;
    if (version == 1) return;
    final bool empty = db
        .select("SELECT name FROM sqlite_master WHERE type = 'table'")
        .isEmpty;
    if (version != 0 || !empty) {
      throw StateError('项目数据库 schema 版本不支持：$path（user_version=$version）');
    }
    db.execute('''
CREATE TABLE project (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  vcs TEXT,
  remote TEXT,
  time_created INTEGER NOT NULL,
  time_updated INTEGER NOT NULL
);
CREATE TABLE worktree (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
  path TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  dir_name TEXT NOT NULL UNIQUE,
  time_created INTEGER NOT NULL,
  time_updated INTEGER NOT NULL
);
CREATE INDEX worktree_project_idx ON worktree(project_id);
PRAGMA user_version = 1;
''');
  }

  static ProjectRecord _projectFrom(Row row) => ProjectRecord(
    id: row['id'] as String,
    name: row['name'] as String,
    vcs: row['vcs'] as String?,
    remote: row['remote'] as String?,
  );

  static WorktreeRecord _worktreeFrom(Row row) => WorktreeRecord(
    id: row['id'] as String,
    projectId: row['project_id'] as String,
    path: row['path'] as String,
    name: row['name'] as String,
    dirName: row['dir_name'] as String,
  );
}

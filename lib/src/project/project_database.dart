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
    this.timeActive = 0,
    this.timeArchived,
    this.iconUrl,
    this.iconColor,
  });

  final String id;
  final String name;
  final String? vcs;
  final String? remote;
  final int timeActive;
  final int? timeArchived;
  final String? iconUrl;
  final String? iconColor;
}

/// `worktree` 表的一行。
class WorktreeRecord {
  const WorktreeRecord({
    required this.id,
    required this.projectId,
    required this.path,
    required this.name,
    required this.dirName,
    this.strategy,
  });

  final String id;
  final String projectId;
  final String path;
  final String name;
  final String dirName;
  final String? strategy;
}

/// 项目注册表数据库；同步 API，生命周期由调用方关闭。
class ProjectDatabase {
  ProjectDatabase._(this.path, this._db);

  /// 打开（必要时创建）数据库。
  factory ProjectDatabase.open(String path) {
    final Directory parent = File(path).parent;
    parent.createSync(recursive: true);
    Database? db;
    try {
      db = sqlite3.open(path);
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA foreign_keys = ON');
      db.execute('PRAGMA busy_timeout = 5000');
      _migrate(db, path);
    } on SqliteException catch (error) {
      db?.dispose();
      throw StateError('项目数据库无法打开或已损坏：$path（${error.message}）');
    } on StateError {
      db?.dispose();
      rethrow;
    } catch (error) {
      db?.dispose();
      throw StateError('项目数据库无法打开或已损坏：$path（$error）');
    }
    _restrictArtifacts(path);
    return ProjectDatabase._(path, db);
  }

  /// 数据库文件路径。
  final String path;
  final Database _db;
  bool _closed = false;

  List<ProjectRecord> projects() => _guard(() {
    final ResultSet rows = _db.select(
      'SELECT * FROM project ORDER BY time_active DESC, time_updated DESC',
    );
    return <ProjectRecord>[for (final Row row in rows) _projectFrom(row)];
  });

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

  /// 全部 worktree，最近更新的在前。
  List<WorktreeRecord> worktrees() => _guard(() {
    final ResultSet rows = _db.select(
      'SELECT * FROM worktree ORDER BY time_updated DESC, path ASC',
    );
    return <WorktreeRecord>[
      for (final Row row in rows) _worktreeFrom(row),
    ];
  });

  /// 在单个事务内执行 [action]；异常时回滚并原样抛出。
  T transaction<T>(T Function() action) {
    try {
      _db.execute('BEGIN IMMEDIATE');
    } on SqliteException catch (error) {
      throw StateError('项目数据库操作失败：$path（${error.message}）');
    }
    try {
      final T result = action();
      _db.execute('COMMIT');
      _restrictArtifacts(path);
      return result;
    } catch (error) {
      try {
        _db.execute('ROLLBACK');
      } on SqliteException {
        // 回滚失败不覆盖原始异常。
      }
      if (error is SqliteException) {
        throw StateError('项目数据库操作失败：$path（${error.message}）');
      }
      rethrow;
    }
  }

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
INSERT INTO project
  (id, name, vcs, remote, time_created, time_updated, time_active)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  vcs = excluded.vcs,
  remote = excluded.remote,
  time_updated = excluded.time_updated
''',
        <Object?>[id, name, vcs, remote, now, now, now],
      );
      _restrictArtifacts(path);
    });
  }

  void saveWorktree({
    required String id,
    required String projectId,
    required String path,
    required String name,
    required String dirName,
    String? strategy,
  }) {
    _guard(() {
      final int now = DateTime.now().millisecondsSinceEpoch;
      _db.execute(
        '''
INSERT INTO worktree
  (id, project_id, path, name, dir_name, strategy, time_created, time_updated)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  project_id = excluded.project_id,
  path = excluded.path,
  name = excluded.name,
  dir_name = excluded.dir_name,
  strategy = excluded.strategy,
  time_updated = excluded.time_updated
''',
        <Object?>[id, projectId, path, name, dirName, strategy, now, now],
      );
      _restrictArtifacts(path);
    });
  }

  void touchProject(String id) {
    _guard(() {
      _db.execute(
        'UPDATE project SET time_active = ?, time_updated = ? WHERE id = ?',
        <Object?>[DateTime.now().millisecondsSinceEpoch, DateTime.now().millisecondsSinceEpoch, id],
      );
    });
  }

  void archiveProject(String id, {bool archived = true}) {
    _guard(() {
      final int? value = archived ? DateTime.now().millisecondsSinceEpoch : null;
      _db.execute(
        'UPDATE project SET time_archived = ?, time_updated = ? WHERE id = ?',
        <Object?>[value, DateTime.now().millisecondsSinceEpoch, id],
      );
    });
  }

  void setProjectIcon(String id, {String? url, String? color}) {
    _guard(() {
      _db.execute(
        'UPDATE project SET icon_url = ?, icon_color = ?, time_updated = ? WHERE id = ?',
        <Object?>[url, color, DateTime.now().millisecondsSinceEpoch, id],
      );
    });
  }

  void deleteWorktree(String id) {
    _guard(() {
      _db.execute('DELETE FROM worktree WHERE id = ?', <Object?>[id]);
      _restrictArtifacts(path);
    });
  }

  void deleteProject(String id) {
    _guard(() {
      _db.execute('DELETE FROM worktree WHERE project_id = ?', <Object?>[id]);
      _db.execute('DELETE FROM project WHERE id = ?', <Object?>[id]);
    });
  }

  void renameProject(String id, String name) {
    _guard(() {
      _db.execute(
        'UPDATE project SET name = ?, time_updated = ? WHERE id = ?',
        <Object?>[name, DateTime.now().millisecondsSinceEpoch, id],
      );
      _restrictArtifacts(path);
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
    if (version == 3) return;
    if (version == 1) {
      db.execute('ALTER TABLE worktree ADD COLUMN strategy TEXT');
      db.execute('PRAGMA user_version = 2');
    }
    if (version == 1 || version == 2) {
      db.execute('ALTER TABLE project ADD COLUMN time_active INTEGER NOT NULL DEFAULT 0');
      db.execute('ALTER TABLE project ADD COLUMN time_archived INTEGER');
      db.execute('ALTER TABLE project ADD COLUMN icon_url TEXT');
      db.execute('ALTER TABLE project ADD COLUMN icon_color TEXT');
      db.execute('PRAGMA user_version = 3');
      return;
    }
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
  time_updated INTEGER NOT NULL,
  time_active INTEGER NOT NULL DEFAULT 0,
  time_archived INTEGER,
  icon_url TEXT,
  icon_color TEXT
);
CREATE TABLE worktree (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
  path TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  dir_name TEXT NOT NULL UNIQUE,
  strategy TEXT,
  time_created INTEGER NOT NULL,
  time_updated INTEGER NOT NULL
);
CREATE INDEX worktree_project_idx ON worktree(project_id);
PRAGMA user_version = 3;
''');
  }

  static ProjectRecord _projectFrom(Row row) => ProjectRecord(
    id: row['id'] as String,
    name: row['name'] as String,
    vcs: row['vcs'] as String?,
    remote: row['remote'] as String?,
    timeActive: (row['time_active'] as int?) ?? 0,
    timeArchived: row['time_archived'] as int?,
    iconUrl: row['icon_url'] as String?,
    iconColor: row['icon_color'] as String?,
  );

  static WorktreeRecord _worktreeFrom(Row row) => WorktreeRecord(
    id: row['id'] as String,
    projectId: row['project_id'] as String,
    path: row['path'] as String,
    name: row['name'] as String,
    dirName: row['dir_name'] as String,
    strategy: row['strategy'] as String?,
  );
}

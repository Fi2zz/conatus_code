/// 项目注册表修复：sidecar 重建、损坏 DB 备份。
library;

import 'dart:io';

import 'package:conatus_code/src/project/project_database.dart';
import 'package:conatus_code/src/project/project_registry.dart';
import 'package:conatus_code/src/project/project_repair.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-repair');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

ProjectRegistry _registry(Directory home) => ProjectRegistry.open(
      env: <String, String>{'HOME': home.path},
    );

String _db(Directory home) => '${home.path}/.nava/projects.db';

void _deleteDb(String path) {
  for (final String suffix in <String>['', '-wal', '-shm']) {
    final File file = File('$path$suffix');
    if (file.existsSync()) file.deleteSync();
  }
}

void main() {
  test('DB 丢失后从 workspace.json 恢复', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = _registry(home);
    final WorkspaceInfo info = registry.resolve(work.path);
    registry.close();
    _deleteDb(_db(home));

    final ProjectRepairReport report = repairProjectRegistry(
      env: <String, String>{'HOME': home.path},
    );

    expect(report.restored, 1);
    expect(report.skipped, 0);
    expect(report.backupPath, isNull);
    final ProjectDatabase db = ProjectDatabase.open(_db(home));
    addTearDown(db.close);
    expect(db.project(info.projectId)!.name, info.projectName);
    expect(db.worktree(info.worktreeId)!.path, info.worktreePath);
  });

  test('DB 损坏时先备份再恢复', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = _registry(home);
    registry.resolve(work.path);
    registry.close();

    final String path = _db(home);
    _deleteDb(path);
    File(path).writeAsStringSync('not a database');

    final ProjectRepairReport report = repairProjectRegistry(
      env: <String, String>{'HOME': home.path},
    );

    expect(report.restored, 1);
    expect(report.backupPath, isNotNull);
    expect(File(report.backupPath!).existsSync(), isTrue);
    final ProjectDatabase db = ProjectDatabase.open(path);
    addTearDown(db.close);
    expect(db.worktrees(), hasLength(1));
  });

  test('缺少 sidecar 时用 DB 补写，再扫描恢复', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = _registry(home);
    registry.resolve(work.path);
    registry.close();
    final Directory workspaces = Directory('${home.path}/.nava/workspaces');
    final Directory dataDir = workspaces.listSync().whereType<Directory>().single;
    File('${dataDir.path}/workspace.json').deleteSync();

    final ProjectRepairReport report = repairProjectRegistry(
      env: <String, String>{'HOME': home.path},
    );

    expect(report.restored, 1);
    expect(
      File('${dataDir.path}/workspace.json').existsSync(),
      isTrue,
    );

    _deleteDb(_db(home));
    final ProjectRepairReport again = repairProjectRegistry(
      env: <String, String>{'HOME': home.path},
    );
    expect(again.restored, 1);
  });

  test('没有 sidecar 的目录计入 skipped', () {
    final Directory home = _tempDir();
    final Directory workspaces = Directory('${home.path}/.nava/workspaces')
      ..createSync(recursive: true);
    Directory('${workspaces.path}/orphan').createSync();

    final ProjectRepairReport report = repairProjectRegistry(
      env: <String, String>{'HOME': home.path},
    );

    expect(report.restored, 0);
    expect(report.skipped, 1);
  });
}

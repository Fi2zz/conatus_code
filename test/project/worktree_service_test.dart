/// nava 自管 git worktree：create / list / remove。
library;

import 'dart:io';

import 'package:conatus_code/src/project/project_registry.dart';
import 'package:conatus_code/src/project/worktree_service.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-worktree');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

void _git(Directory dir, List<String> args) {
  final ProcessResult result = Process.runSync(
    'git',
    args,
    workingDirectory: dir.path,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

Directory _repo() {
  final Directory repo = _tempDir();
  _git(repo, <String>['init', '-q', '-b', 'main']);
  _git(repo, <String>['config', 'user.email', 'test@example.com']);
  _git(repo, <String>['config', 'user.name', 'test']);
  File('${repo.path}/a.txt').writeAsStringSync('a');
  _git(repo, <String>['add', 'a.txt']);
  _git(repo, <String>['commit', '-qm', 'init']);
  return repo;
}

void main() {
  test('create 创建真实 worktree、登记 strategy 并分配数据目录', () async {
    final Directory home = _tempDir();
    final Directory repo = _repo();
    final ProjectRegistry registry = ProjectRegistry.open(
      dbPath: '${home.path}/projects.db',
      workspacesDir: '${home.path}/workspaces',
    );
    addTearDown(registry.close);
    final WorktreeService service = WorktreeService(
      registry: registry,
      workdir: repo.path,
      worktreesDir: '${home.path}/worktrees',
    );

    final WorktreeCreateResult created = await service.create('feature');

    expect(Directory(created.path).existsSync(), isTrue);
    expect(created.branch, 'feature');
    expect(File('${created.path}/a.txt').existsSync(), isTrue);
    final List<WorkspaceInfo> list = service.list();
    final WorkspaceInfo tracked = list.firstWhere(
      (WorkspaceInfo item) => item.worktreePath == created.info.worktreePath,
    );
    expect(tracked.strategy, 'git');
    expect(Directory(tracked.dataDir).existsSync(), isTrue);
    expect(tracked.worktreePath, contains('/worktrees/'));
  });

  test('remove 删除 worktree、登记行与数据目录', () async {
    final Directory home = _tempDir();
    final Directory repo = _repo();
    final ProjectRegistry registry = ProjectRegistry.open(
      dbPath: '${home.path}/projects.db',
      workspacesDir: '${home.path}/workspaces',
    );
    addTearDown(registry.close);
    final WorktreeService service = WorktreeService(
      registry: registry,
      workdir: repo.path,
      worktreesDir: '${home.path}/worktrees',
    );
    final WorktreeCreateResult created = await service.create('feature');
    final String dataDir = created.info.dataDir;

    await service.remove('feature');

    expect(Directory(created.path).existsSync(), isFalse);
    expect(Directory(dataDir).existsSync(), isFalse);
    expect(
      service.list().where(
            (WorkspaceInfo item) => item.worktreePath == created.info.worktreePath,
          ),
      isEmpty,
    );
  });

  test('拒绝删除非 nava 管理的 worktree', () async {
    final Directory home = _tempDir();
    final Directory repo = _repo();
    final ProjectRegistry registry = ProjectRegistry.open(
      dbPath: '${home.path}/projects.db',
      workspacesDir: '${home.path}/workspaces',
    );
    addTearDown(registry.close);
    final WorktreeService service = WorktreeService(
      registry: registry,
      workdir: repo.path,
      worktreesDir: '${home.path}/worktrees',
    );

    await expectLater(service.remove('main'), throwsStateError);
  });
}

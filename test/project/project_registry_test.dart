/// 项目注册表：解析、目录分配、重命名与损坏 DB。
library;

import 'dart:io';

import 'package:conatus_code/src/project/project_database.dart';
import 'package:conatus_code/src/project/project_identity.dart';
import 'package:conatus_code/src/project/project_paths.dart';
import 'package:conatus_code/src/project/project_registry.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-registry');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

String _git(Directory dir, List<String> args) {
  final ProcessResult result = Process.runSync(
    'git',
    args,
    workingDirectory: dir.path,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (result.stdout as String).trim();
}

void _initRepo(Directory dir, {String? remote}) {
  _git(dir, <String>['init', '-q', '-b', 'main']);
  _git(dir, <String>['config', 'user.email', 'test@example.com']);
  _git(dir, <String>['config', 'user.name', 'test']);
  File('${dir.path}${Platform.pathSeparator}a.txt').writeAsStringSync('a');
  _git(dir, <String>['add', 'a.txt']);
  _git(dir, <String>['commit', '-qm', 'init']);
  if (remote != null) {
    _git(dir, <String>['remote', 'add', 'origin', remote]);
  }
}

ProjectRegistry _registry(Directory home) =>
    ProjectRegistry.open(env: <String, String>{'HOME': home.path});

void main() {
  test('非 git 目录：建库、登记项目/worktree 并创建目录', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = _registry(home);
    addTearDown(registry.close);

    final WorkspaceInfo info = registry.resolve(work.path);

    expect(File('${home.path}/.nava/projects.db').existsSync(), isTrue);
    expect(info.projectName, work.path.split(Platform.pathSeparator).last);
    expect(info.projectId, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(info.dataDir, startsWith('${home.path}/.nava/workspaces/'));
    expect(Directory(info.dataDir).existsSync(), isTrue);
  });

  test('同一路径重复 resolve 幂等', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = _registry(home);
    addTearDown(registry.close);

    final WorkspaceInfo first = registry.resolve(work.path);
    final WorkspaceInfo second = registry.resolve(work.path);

    expect(second.dataDir, first.dataDir);
    expect(second.worktreeId, first.worktreeId);
  });

  test('同 remote 两个 worktree：共享项目、目录独立', () {
    final Directory home = _tempDir();
    final Directory repo = _tempDir();
    final Directory other = _tempDir();
    _initRepo(repo, remote: 'https://github.com/acme/lifts.git');
    _initRepo(other, remote: 'https://github.com/acme/lifts.git');
    final ProjectRegistry registry = _registry(home);
    addTearDown(registry.close);

    final WorkspaceInfo a = registry.resolve(repo.path);
    final WorkspaceInfo b = registry.resolve(other.path);

    expect(a.projectId, b.projectId);
    expect(a.worktreeId, isNot(b.worktreeId));
    expect(a.dataDir, isNot(b.dataDir));
    expect(Directory(a.dataDir).existsSync(), isTrue);
    expect(Directory(b.dataDir).existsSync(), isTrue);
  });

  test('同 basename 仍分配不同目录', () {
    final Directory home = _tempDir();
    final Directory a = _tempDir();
    final Directory b = _tempDir();
    _initRepo(a);
    _initRepo(b);
    final ProjectRegistry registry = _registry(home);
    addTearDown(registry.close);

    final WorkspaceInfo first = registry.resolve(a.path);
    final WorkspaceInfo second = registry.resolve(b.path);

    expect(first.dataDir, isNot(second.dataDir));
  });

  test('resolve 写 workspace.json，rename 同步 sidecar', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = _registry(home);
    addTearDown(registry.close);
    final WorkspaceInfo info = registry.resolve(work.path);

    final File sidecar = File('${info.dataDir}/workspace.json');
    expect(sidecar.existsSync(), isTrue);
    final String before = sidecar.readAsStringSync();
    expect(before, contains(info.projectId));
    expect(before, contains(info.worktreePath));

    registry.rename(info.projectId, '改名后', dataDir: info.dataDir);
    final String after = sidecar.readAsStringSync();
    expect(after, contains('"projectName":"改名后"'));
  });

  test('list 返回已登记 worktree 与项目名', () {
    final Directory home = _tempDir();
    final Directory a = _tempDir();
    final Directory b = _tempDir();
    _initRepo(a, remote: 'https://github.com/acme/lifts.git');
    _initRepo(b, remote: 'https://github.com/acme/lifts.git');
    final ProjectRegistry registry = _registry(home);
    addTearDown(registry.close);
    final WorkspaceInfo first = registry.resolve(a.path);
    registry.resolve(b.path);

    final List<WorkspaceInfo> list = registry.list();

    expect(list, hasLength(2));
    expect(list.map((WorkspaceInfo item) => item.worktreePath),
        containsAll(<String>[first.worktreePath, Directory(b.path).resolveSymbolicLinksSync()]));
    expect(list.every((WorkspaceInfo item) => item.projectName == first.projectName),
        isTrue);
  });

  test('rename 持久化，后续 resolve 不覆盖', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = _registry(home);
    final WorkspaceInfo info = registry.resolve(work.path);
    registry.rename(info.projectId, '我的项目');
    registry.close();

    final ProjectRegistry reopened = _registry(home);
    addTearDown(reopened.close);
    final WorkspaceInfo again = reopened.resolve(work.path);
    expect(again.projectName, '我的项目');
  });

  test('rename 拒绝空、超长与控制字符', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = _registry(home);
    addTearDown(registry.close);
    final WorkspaceInfo info = registry.resolve(work.path);

    expect(() => registry.rename(info.projectId, '  '), throwsArgumentError);
    expect(
      () => registry.rename(info.projectId, 'a' * 81),
      throwsArgumentError,
    );
    expect(() => registry.rename(info.projectId, 'a\nb'), throwsArgumentError);
  });

  test('dataDirOverride 不改变目录分配但仍登记 worktree', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final Directory override = _tempDir();
    final ProjectRegistry registry = _registry(home);
    addTearDown(registry.close);

    final WorkspaceInfo info = registry.resolve(
      work.path,
      dataDirOverride: override.path,
    );

    expect(info.dataDir, override.path);
    expect(Directory(override.path).existsSync(), isTrue);
  });

  test('相对 dataDirOverride 基于 worktree 根', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = _registry(home);
    addTearDown(registry.close);

    final WorkspaceInfo info = registry.resolve(
      work.path,
      dataDirOverride: 'relative-data',
    );

    expect(
      info.dataDir,
      '${Directory(work.path).resolveSymbolicLinksSync()}'
      '${Platform.pathSeparator}relative-data',
    );
  });

  test('相对 project_dir 以启动目录为基准，而不是 git 根', () {
    final Directory home = _tempDir();
    final Directory repo = _tempDir();
    _initRepo(repo);
    final Directory sub = Directory('${repo.path}/sub')..createSync();
    final ProjectRegistry registry = _registry(home);
    addTearDown(registry.close);

    final WorkspaceInfo info = registry.resolve(
      sub.path,
      dataDirOverride: '.conatus',
    );

    expect(
      info.dataDir,
      '${Directory(sub.path).resolveSymbolicLinksSync()}'
      '${Platform.pathSeparator}.conatus',
    );
  });

  test('12 位目录名冲突时扩展到 16 位', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = _registry(home);
    addTearDown(registry.close);
    final ProjectIdentity identity = resolveProjectIdentity(work.path);
    final String candidate = workspaceDirName(
      identity.name,
      identity.worktreeId,
    );
    final ProjectDatabase db = ProjectDatabase.open(
      '${home.path}/.nava/projects.db',
    );
    addTearDown(db.close);
    db.saveProject(id: 'other-project', name: 'other');
    db.saveWorktree(
      id: 'other-worktree',
      projectId: 'other-project',
      path: '/tmp/other',
      name: 'other',
      dirName: candidate,
    );

    final WorkspaceInfo info = registry.resolve(work.path);

    expect(info.dataDir, isNot(endsWith(candidate)));
    expect(info.dataDir, endsWith(identity.worktreeId.substring(0, 16)));
  });

  test('拒绝 .opencode 下的注册表路径', () {
    final Directory home = _tempDir();
    expect(
      () => ProjectRegistry.open(
        env: <String, String>{'HOME': '${home.path}/.opencode'},
      ),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('.opencode'),
        ),
      ),
    );
  });

  test('拒绝 projectDir 落在 .opencode', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = _registry(home);
    addTearDown(registry.close);

    expect(
      () => registry.resolve(
        work.path,
        dataDirOverride: '${work.path}/.opencode/state',
      ),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('.opencode'),
        ),
      ),
    );
  });

  test('损坏 DB 冒泡路径', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    Directory('${home.path}/.nava').createSync(recursive: true);
    File('${home.path}/.nava/projects.db').writeAsStringSync('not a database');

    expect(
      () => _registry(home).resolve(work.path),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('${home.path}/.nava/projects.db'),
        ),
      ),
    );
  });
}

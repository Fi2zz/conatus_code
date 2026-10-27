/// 项目身份：非 git / remote / root commit / 子目录启动。
library;

import 'dart:io';

import 'package:conatus_code/src/project/project_identity.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-identity');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

String _canonical(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return Directory(path).absolute.path;
  }
}

void _git(Directory dir, List<String> args) {
  final ProcessResult result = Process.runSync(
    'git',
    args,
    workingDirectory: dir.path,
  );
  expect(result.exitCode, 0, reason: 'git ${args.join(' ')}: ${result.stderr}');
}

void _initRepo(Directory dir) {
  _git(dir, <String>['init', '-q', '-b', 'main']);
  _git(dir, <String>['config', 'user.email', 'test@example.com']);
  _git(dir, <String>['config', 'user.name', 'test']);
  File('${dir.path}${Platform.pathSeparator}a.txt').writeAsStringSync('a');
  _git(dir, <String>['add', 'a.txt']);
  _git(dir, <String>['commit', '-qm', 'init']);
}

Directory _clone(Directory source, String name) {
  final Directory parent = _tempDir();
  final Directory target = Directory('${parent.path}/$name');
  final ProcessResult result = Process.runSync('git', <String>[
    'clone',
    '-q',
    source.path,
    target.path,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return target;
}

void main() {
  test('非 git 目录：路径哈希、稳定、worktree 路径规范化', () {
    final Directory dir = _tempDir();
    final ProjectIdentity first = resolveProjectIdentity(dir.path);
    final ProjectIdentity second = resolveProjectIdentity('${dir.path}/');

    expect(first.vcs, isNull);
    expect(first.remote, isNull);
    expect(first.projectId, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(first.worktreeId, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(first.projectId, second.projectId);
    expect(first.worktreeId, second.worktreeId);
    expect(first.worktreePath, _canonical(dir.path));
    expect(first.name, dir.path.split(Platform.pathSeparator).last);
  });

  test('git remote：项目 ID 来自规范化 remote', () {
    final Directory repo = _tempDir();
    _initRepo(repo);
    _git(repo, <String>[
      'remote',
      'add',
      'origin',
      'https://github.com/acme/lifts.git',
    ]);

    final ProjectIdentity identity = resolveProjectIdentity(repo.path);

    expect(identity.vcs, 'git');
    expect(identity.remote, 'github.com/acme/lifts');
    expect(identity.projectId, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(identity.worktreePath, _canonical(repo.path));
    expect(identity.name, repo.path.split(Platform.pathSeparator).last);
  });

  test('同 remote 的两个 clone：共享 projectId，worktree 独立', () {
    final Directory repo = _tempDir();
    _initRepo(repo);
    _git(repo, <String>[
      'remote',
      'add',
      'origin',
      'git@github.com:acme/lifts.git',
    ]);
    final Directory cloneA = _clone(repo, 'a');
    final Directory cloneB = _clone(repo, 'b');
    for (final Directory clone in <Directory>[cloneA, cloneB]) {
      _git(clone, <String>[
        'remote',
        'set-url',
        'origin',
        'git@github.com:acme/lifts.git',
      ]);
    }

    final ProjectIdentity a = resolveProjectIdentity(cloneA.path);
    final ProjectIdentity b = resolveProjectIdentity(cloneB.path);

    expect(a.projectId, b.projectId);
    expect(a.worktreeId, isNot(b.worktreeId));
    expect(a.worktreePath, isNot(b.worktreePath));
    expect(a.remote, 'github.com/acme/lifts');
  });

  test('无 remote 的 clone：共享 root commit 身份', () {
    final Directory repo = _tempDir();
    _initRepo(repo);
    final Directory clone = _clone(repo, 'clone');

    final ProjectIdentity original = resolveProjectIdentity(repo.path);
    final ProjectIdentity copied = resolveProjectIdentity(clone.path);

    expect(original.remote, isNull);
    expect(copied.remote, isNull);
    expect(original.projectId, copied.projectId);
    expect(original.worktreeId, isNot(copied.worktreeId));
  });

  test('从 git 子目录启动：worktree 根仍是仓库根', () {
    final Directory repo = _tempDir();
    _initRepo(repo);
    final Directory sub = Directory('${repo.path}/sub')..createSync();

    final ProjectIdentity identity = resolveProjectIdentity(sub.path);

    expect(identity.vcs, 'git');
    expect(identity.worktreePath, _canonical(repo.path));
    expect(identity.projectId, resolveProjectIdentity(repo.path).projectId);
  });
}

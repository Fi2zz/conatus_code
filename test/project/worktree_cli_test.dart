/// `nava worktree` CLI。
library;

import 'dart:io';

import 'package:conatus_code/src/project/worktree_cli.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-worktree-cli');
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
  test('list / new / remove', () async {
    final Directory home = _tempDir();
    final Directory repo = _repo();
    final Map<String, String> env = <String, String>{'HOME': home.path};

    expect(await runWorktreeCli(<String>['new', 'feature'], env: env, workdir: repo.path), 0);
    final Directory target = Directory('${home.path}/.nava/worktrees');
    expect(target.existsSync(), isTrue);
    final Directory checkout = target
        .listSync(recursive: true)
        .whereType<Directory>()
        .firstWhere((Directory dir) => dir.path.endsWith('/feature'));
    expect(File('${checkout.path}/a.txt').existsSync(), isTrue);

    expect(await runWorktreeCli(<String>['list'], env: env, workdir: repo.path), 0);
    expect(
      await runWorktreeCli(<String>['remove', 'feature', '--purge'], env: env, workdir: repo.path),
      0,
    );
    expect(checkout.existsSync(), isFalse);
  });
}

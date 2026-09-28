/// 全局 gitignore 排除 + 敏感文件排除：只认全局、不认工作区 .gitignore。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

late Directory _ws;
late String _root;
late String _gitDir;
late File _globalIgnore;

void _write(String rel, String content) {
  final File f = File('$_root${Platform.pathSeparator}$rel');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(content);
}

void main() {
  setUp(() {
    _ws = Directory.systemTemp.createTempSync('nava-gg');
    addTearDown(() => _ws.deleteSync(recursive: true));
    _root = _ws.path;
    final Directory proj = Directory('$_root${Platform.pathSeparator}.conatus')
      ..createSync();
    _gitDir =
        '${proj.path}${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}shadow.git';
    Directory(_gitDir).parent.createSync(recursive: true);
    Process.runSync('git', <String>['init', '--quiet', _root]);

    final Directory home = Directory.systemTemp.createTempSync('nava-home');
    addTearDown(() => home.deleteSync(recursive: true));
    _globalIgnore = File('${home.path}/ignore')
      ..writeAsStringSync('*.log\n.DS_Store\nsecret-*\n');
  });

  Future<Set<String>> resolve(List<String> candidates) async {
    const ProcessGitRunner base = ProcessGitRunner();
    await base.run(
      <String>['init', '--quiet'],
      gitDir: _gitDir,
      workTree: _root,
    );
    return resolveGlobalGitIgnore(
      git: _GlobalIgnoreRunner(base, _globalIgnore.path),
      gitDir: _gitDir,
      workTree: _root,
      candidates: candidates,
    );
  }

  test('只采纳全局 excludesFile 的忽略，剔除工作区 .gitignore 的', () async {
    _write('.gitignore', 'project-only.txt\nbuild/\n');
    _write('project-only.txt', 'x');
    _write('debug.log', 'x');
    _write('.DS_Store', 'x');
    _write('secret-key.txt', 'x');
    _write('keep.dart', 'x');

    final Set<String> ignored = await resolve(<String>[
      'project-only.txt',
      'debug.log',
      '.DS_Store',
      'secret-key.txt',
      'keep.dart',
    ]);

    expect(
      ignored,
      containsAll(<String>['debug.log', '.DS_Store', 'secret-key.txt']),
      reason: '全局 ignore 命中的应被排除',
    );
    expect(ignored, isNot(contains('keep.dart')), reason: '两边都不命中');
    expect(
      ignored,
      isNot(contains('project-only.txt')),
      reason: '只有工作区 .gitignore 命中——「不进版本库」不等于「不该备份」',
    );
  });

  test('未配置全局 excludesFile 时返回空集（保守降级）', () async {
    const ProcessGitRunner base = ProcessGitRunner();
    await base.run(
      <String>['init', '--quiet'],
      gitDir: _gitDir,
      workTree: _root,
    );
    final Set<String> ignored = await resolveGlobalGitIgnore(
      // 指向一个不存在的文件 = 等价于未配置
      git: const _GlobalIgnoreRunner(ProcessGitRunner(), '/nonexistent/ignore'),
      gitDir: _gitDir,
      workTree: _root,
      candidates: <String>['a.txt', 'b.txt'],
    );
    expect(ignored, isEmpty, reason: '解析不出就退回 conatus 自己的规则');
  });

  test('候选集为空时不问 git', () async {
    final Set<String> ignored = await resolveGlobalGitIgnore(
      git: const UnavailableGitRunner(),
      gitDir: _gitDir,
      workTree: _root,
      candidates: const <String>[],
    );
    expect(ignored, isEmpty);
  });

  group('敏感文件排除', () {
    test('凭据 / 私钥类文件名与后缀被排除', () {
      for (final String p in <String>[
        '.env',
        'a/b/.env',
        '.env.local',
        '.env.production',
        'server.pem',
        'deep/nested/app.key',
        'id_rsa',
        'config/credentials.json',
        'secrets.yaml',
        '.netrc',
        'cert.p12',
      ]) {
        expect(
          checkpointExcluded(p, '', const <String>[]),
          isTrue,
          reason: '$p 应被排除',
        );
      }
    });

    test('.env 的模板变体照常进快照', () {
      for (final String p in <String>[
        '.env.example',
        '.env.sample',
        '.env.template',
        '.env.defaults',
      ]) {
        expect(
          checkpointExcluded(p, '', const <String>[]),
          isFalse,
          reason: '$p 不含真实凭据',
        );
      }
    });

    test('同名不同物的普通文件不受影响', () {
      for (final String p in <String>[
        'lib/env.dart',
        'lib/keys.dart',
        'pubspec.lock',
        'src/credential_manager.dart',
        '.envrc', // direnv 配置，非凭据
      ]) {
        expect(
          checkpointExcluded(p, '', const <String>[]),
          isFalse,
          reason: '$p 不该被误伤',
        );
      }
    });
  });
}

/// 给执行器套一个固定的 `core.excludesFile`，模拟用户的全局 git 配置。
class _GlobalIgnoreRunner implements GitRunner {
  const _GlobalIgnoreRunner(this.inner, this.excludesFile);

  final GitRunner inner;
  final String excludesFile;

  List<String> _wrap(List<String> args) => <String>[
    '-c',
    'core.excludesFile=$excludesFile',
    ...args,
  ];

  @override
  Future<bool> available() => inner.available();

  @override
  Future<GitResult> run(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) => inner.run(_wrap(args), gitDir: gitDir, workTree: workTree);

  @override
  GitResult runSync(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) => (inner as ProcessGitRunner).runSync(
    _wrap(args),
    gitDir: gitDir,
    workTree: workTree,
  );
}

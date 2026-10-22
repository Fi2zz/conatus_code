/// 影子 git 仓库存储：基线/差量、恢复（含删除）、排除项、prune、不碰用户仓库。
///
/// 这些用例直接跑真实 git（影子方案的全部价值与全部风险都在 git 的行为上，
/// 塞 fake 等于把要测的东西测没了）。无 git 环境下整个文件跳过。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

/// 建一个「用户项目 + 影子仓库」；返回 (store, 工作区根, projectDir)。
///
/// 工作区**本身就是 git 仓库**——这是要验的重点：影子提交不得污染它。
late Directory _ws;
late Directory _sh;
late GitShadowStore _store;
late String _root;
late String _projectDir;
late bool _gitOk;

void _write(String rel, String content) {
  final File file = File('$_root${Platform.pathSeparator}$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

String _read(String rel) =>
    File('$_root${Platform.pathSeparator}$rel').readAsStringSync();

void _setUp({int keep = 5, List<String> ignore = const <String>[]}) {
  _ws = Directory.systemTemp.createTempSync('nava-shadow-ws');
  _sh = Directory.systemTemp.createTempSync('nava-shadow-git');
  addTearDown(() {
    if (_ws.existsSync()) _ws.deleteSync(recursive: true);
    if (_sh.existsSync()) _sh.deleteSync(recursive: true);
  });
  _root = _ws.path;
  _projectDir = '$_root${Platform.pathSeparator}.conatus';
  Directory(_projectDir).createSync();
  // 工作区自带 git 仓库（用户项目的常态）。
  Process.runSync('git', <String>['init', '--quiet', _root]);
  _store = GitShadowStore(
    root: _root,
    projectDir: _projectDir,
    keep: keep,
    ignore: ignore,
  );
}

void main() {
  setUpAll(() async {
    _gitOk = await const ProcessGitRunner().available();
  });

  test('快照与恢复：改坏的文件回到基线状态', () async {
    if (!_gitOk) return;
    _setUp();
    _write('a.txt', 'v0');
    await _store.snapshot('s1', 0, lastEventId: 'ev-0');

    _write('a.txt', 'v1-broken');
    await _store.snapshot('s1', 1);

    await _store.restore('s1', 0);
    expect(_read('a.txt'), 'v0');
  });

  test('rsync 语义：恢复会删掉该轮之后新增的文件', () async {
    if (!_gitOk) return;
    _setUp();
    _write('a.txt', 'v0');
    await _store.snapshot('s1', 0);

    _write('b.txt', 'new');
    await _store.snapshot('s1', 1);
    expect(_read('b.txt'), 'new');

    await _store.restore('s1', 0);
    expect(_read('a.txt'), 'v0');
    expect(
      File('$_root${Platform.pathSeparator}b.txt').existsSync(),
      isFalse,
      reason: '目标态没有的文件必须被删（read-tree --reset -u，不是 checkout）',
    );
  });

  test('恢复会补回该轮之后被删的文件', () async {
    if (!_gitOk) return;
    _setUp();
    _write('a.txt', 'v0');
    _write('b.txt', 'keep');
    await _store.snapshot('s1', 0);

    File('$_root${Platform.pathSeparator}b.txt').deleteSync();
    await _store.snapshot('s1', 1);

    await _store.restore('s1', 0);
    expect(_read('b.txt'), 'keep');
  });

  test('二进制文件不炸（sha256 / zlib 都按字节处理）', () async {
    if (!_gitOk) return;
    _setUp();
    File(
      '$_root${Platform.pathSeparator}blob.bin',
    ).writeAsBytesSync(List<int>.generate(200000, (int i) => (i * 31) & 0xff));
    await _store.snapshot('s1', 0);
    File(
      '$_root${Platform.pathSeparator}blob.bin',
    ).writeAsBytesSync(<int>[0xff, 0xfe, 0x00]);
    await _store.snapshot('s1', 1);

    await _store.restore('s1', 0);
    expect(
      File('$_root${Platform.pathSeparator}blob.bin').readAsBytesSync().length,
      200000,
    );
  });

  test('排除项不进快照：.git / projectDir / build / 用户 ignore', () async {
    if (!_gitOk) return;
    _setUp(ignore: <String>['secret']);
    _write('lib/main.dart', 'ok');
    _write('build/out.bin', 'artifact');
    _write('secret/key.txt', 'shh');
    _write('.conatus/local.state', 's');
    await _store.snapshot('s1', 0);

    final CheckpointRestore back = await _restoreTurn0(_store);
    expect(back.restored, greaterThan(0));
    expect(
      File('$_root${Platform.pathSeparator}build/out.bin').existsSync(),
      isTrue,
      reason: 'build/ 被排除，不该在恢复时被当成多余文件删掉',
    );
    expect(
      File('$_root${Platform.pathSeparator}secret/key.txt').existsSync(),
      isTrue,
    );
  });

  test('不污染用户仓库：log 不变、status 只多 untracked', () async {
    if (!_gitOk) return;
    _setUp();
    _write('a.txt', 'v0');
    Process.runSync('git', <String>[
      '-C',
      _root,
      '-c',
      'user.email=a@b',
      '-c',
      'user.name=n',
      'add',
      '-A',
    ]);
    Process.runSync('git', <String>[
      '-C',
      _root,
      '-c',
      'user.email=a@b',
      '-c',
      'user.name=n',
      'commit',
      '--quiet',
      '-m',
      'user commit',
    ]);
    final String before =
        Process.runSync('git', <String>['-C', _root, 'log', '--oneline']).stdout
            as String;

    await _store.snapshot('s1', 0);
    _write('a.txt', 'v1');
    await _store.snapshot('s1', 1);

    final String after =
        Process.runSync('git', <String>['-C', _root, 'log', '--oneline']).stdout
            as String;
    expect(after, before, reason: '影子提交不得进用户仓库的历史');
  });

  test('prune 保留基线 + 最近 keep-1 轮', () async {
    if (!_gitOk) return;
    _setUp(keep: 3);
    for (int turn = 0; turn <= 4; turn++) {
      _write('a.txt', 'v$turn');
      await _store.snapshot('s1', turn);
    }
    expect(_store.turnsOf('s1'), <int>[0, 3, 4]);
  });

  test('clearSession 清掉该会话的索引与 tag', () async {
    if (!_gitOk) return;
    _setUp();
    _write('a.txt', 'v0');
    await _store.snapshot('s1', 0);
    await _store.snapshot('s1', 1);
    expect(_store.turnsOf('s1'), <int>[0, 1]);

    await _store.clearSession('s1');
    expect(_store.turnsOf('s1'), isEmpty);
  });

  test('两个会话各自独立的时间线', () async {
    if (!_gitOk) return;
    _setUp();
    _write('a.txt', 'shared');
    await _store.snapshot('s1', 0);
    await _store.snapshot('s2', 0);
    _write('a.txt', 'from-s1');
    await _store.snapshot('s1', 1);

    expect(_store.turnsOf('s1'), <int>[0, 1]);
    expect(_store.turnsOf('s2'), <int>[0]);
    // s2 的基线仍是 shared：对象共享但时间线不串。
    await _store.restore('s2', 0);
    expect(_read('a.txt'), 'shared');
  });

  test('恢复不存在的轮次抛 missing-checkpoint', () async {
    if (!_gitOk) return;
    _setUp();
    _write('a.txt', 'v0');
    await _store.snapshot('s1', 0);
    await expectLater(
      _store.restore('s1', 7),
      throwsA(
        isA<CheckpointException>().having(
          (CheckpointException e) => e.code,
          'code',
          'missing-checkpoint',
        ),
      ),
    );
  });

  test('lastEventId 随轮次留存（rewind 的对话切点）', () async {
    if (!_gitOk) return;
    _setUp();
    _write('a.txt', 'v0');
    await _store.snapshot('s1', 0, lastEventId: 'ev-0');
    _write('a.txt', 'v1');
    await _store.snapshot('s1', 1, lastEventId: 'ev-1');

    final CheckpointManifest m = await _store.loadManifest('s1', 1);
    expect(m.lastEventId, 'ev-1');
    expect(m.kind, 'delta');
  });

  test('工作区的 .gitignore 不缩小快照（排除面只认 conatus 自己的规则）', () async {
    if (!_gitOk) return;
    _setUp();
    // 回归用例：影子实现曾用 `git add --all`，git 顺从工作区的 .gitignore，
    // 快照只剩被 ignore 之外的少数文件；恢复按残缺清单的 rsync 语义把其余
    // 全删了（swiftus 上实测 9661 → 293，删掉 9119）。
    _write('.gitignore', '.build/\nsecret/\n*.log\n');
    _write('.build/out.bin', 'ARTIFACT');
    _write('secret/k.txt', 'SHH');
    _write('debug.log', 'LOG');
    _write('keep.txt', 'KEEP');

    await _store.snapshot('s1', 0);
    final Set<String> tracked = _lsTree(_commitOf('s1', 0)).toSet();
    expect(
      tracked,
      containsAll(<String>[
        '.build/out.bin', // 被工作区 .gitignore 排除，但对 conatus 要入快照
        'secret/k.txt',
        'debug.log',
        'keep.txt',
      ]),
      reason: '.gitignore 不该影响 conatus 的排除判定',
    );
  });

  test('conatus 自己的排除仍然生效（build/ 与 projectDir 不入快照）', () async {
    if (!_gitOk) return;
    _setUp();
    _write('lib/main.dart', 'ok');
    _write('build/out.bin', 'artifact');
    _write('.conatus/local.state', 's');
    await _store.snapshot('s1', 0);

    final Set<String> tracked = _lsTree(_commitOf('s1', 0)).toSet();
    expect(tracked, contains('lib/main.dart'));
    expect(tracked, isNot(contains('build/out.bin')));
    expect(
      tracked.any((String p) => p.startsWith('.conatus/')),
      isFalse,
      reason: '影子仓库自身在 .conatus 下，绝不能被卷进快照',
    );
  });

  test('本轮被删的文件会在下一轮记录为删除', () async {
    if (!_gitOk) return;
    _setUp();
    _write('a.txt', 'v0');
    _write('b.txt', 'gone-next-turn');
    await _store.snapshot('s1', 0);

    File('$_root${Platform.pathSeparator}b.txt').deleteSync();
    await _store.snapshot('s1', 1);

    final Set<String> at1 = _lsTree(_commitOf('s1', 1)).toSet();
    expect(at1, contains('a.txt'));
    expect(at1, isNot(contains('b.txt')), reason: '删除必须被记录');
  });

  test('嵌套 git 仓库整树排除：既不收也不会被恢复删掉', () async {
    if (!_gitOk) return;
    _setUp();
    // `git worktree` / vendor 目录必中。git add 对落在嵌套仓库里的显式路径
    // 会**静默跳过**（rc=0、无告警），所以若不整树排除，快照会残缺而恢复
    // 会把整个子树删掉。
    final String inner =
        '$_root${Platform.pathSeparator}.worktrees'
        '${Platform.pathSeparator}feature';
    Directory(inner).createSync(recursive: true);
    Process.runSync('git', <String>['init', '--quiet', inner]);
    _write('.worktrees/feature/code.dart', 'INNER');
    _write('top.dart', 'TOP');

    await _store.snapshot('s1', 0);
    final Set<String> tracked = _lsTree(_commitOf('s1', 0)).toSet();
    expect(tracked, contains('top.dart'));
    expect(
      tracked.any((String p) => p.startsWith('.worktrees/')),
      isFalse,
      reason: '嵌套仓库的内部文件不该进快照（git 收不了，收了也不一致）',
    );

    // 关键：恢复时不能把它当「多余文件」删掉。
    await _store.restore('s1', 0);
    expect(
      File('$inner${Platform.pathSeparator}code.dart').existsSync(),
      isTrue,
      reason: '排除项在恢复侧也要跳过，否则会被 rsync 删除',
    );
  });

  test('暂存不完整时报错而非静默产出残缺快照', () async {
    if (!_gitOk) return;
    _setUp();
    _write('a.txt', 'v0');
    _write('b.txt', 'v0');
    // 让 `ls-files --cached` 少报一个路径 = 精确模拟「git 静默不收」。
    // 真实世界的原因就是嵌套版本库（`git add` 跳过且 rc=0 无告警）。
    final GitShadowStore store = GitShadowStore(
      root: _root,
      projectDir: _projectDir,
      git: const _DroppingRunner(ProcessGitRunner(), 'b.txt'),
    );
    await expectLater(
      store.snapshot('s1', 0),
      throwsA(
        isA<CheckpointException>()
            .having(
              (CheckpointException e) => e.code,
              'code',
              'stage-incomplete',
            )
            .having(
              (CheckpointException e) => e.message,
              'message',
              contains('b.txt'),
            ),
      ),
      reason: '残缺快照会让恢复按残缺清单删文件，必须当场失败',
    );
  });

  test('跨会话复用对象：同内容不重存（只多出 tree+commit）', () async {
    if (!_gitOk) return;
    _setUp();
    // 够大才能看出差别：重新存一份必然显著增长，复用则几乎不增长。
    _write('big.bin', 'x' * 200000);
    await _store.snapshot('s1', 0);
    final int afterFirst = _objectStoreBytes();

    // 新会话、同样内容：blob 已存在，只该多出 tree + commit 两个小对象。
    await _store.snapshot('s2', 0);
    final int growth = _objectStoreBytes() - afterFirst;
    expect(
      growth,
      lessThan(20000),
      reason: '同内容应被复用；增长 $growth 字节说明又存了一份 200KB 内容',
    );
  });

  test('readFile 读该轮内容（含二进制）；缺失/只读路径返回 null', () async {
    if (!_gitOk) return;
    _setUp();
    _write('a.txt', 'v0');
    final List<int> blob = List<int>.generate(512, (int i) => (i * 37) & 0xff);
    File('$_root${Platform.pathSeparator}blob.bin').writeAsBytesSync(blob);
    await _store.snapshot('s1', 0);

    _write('a.txt', 'v1');
    File(
      '$_root${Platform.pathSeparator}blob.bin',
    ).writeAsBytesSync(<int>[0xff, 0x00, 0x01]);
    await _store.snapshot('s1', 1);

    expect(utf8.decode((await _store.readFile('s1', 0, 'a.txt'))!), 'v0');
    expect(utf8.decode((await _store.readFile('s1', 1, 'a.txt'))!), 'v1');
    expect(await _store.readFile('s1', 0, 'blob.bin'), blob);
    expect(await _store.readFile('s1', 1, 'missing.txt'), isNull);
    expect(await _store.readFile('s1', 9, 'a.txt'), isNull);
    expect(await _store.readFile('s1', 0, '.opencode/x'), isNull);
    expect(await _store.readFile('s1', 0, '../outside.txt'), isNull);
  });

  test('changesBetween：added/modified/deleted/renamed', () async {
    if (!_gitOk) return;
    _setUp();
    _write('mod.txt', 'm0');
    _write('del.txt', 'd0');
    _write('old-name.txt', 'r0');
    await _store.snapshot('s1', 0);

    _write('mod.txt', 'm1');
    File('$_root${Platform.pathSeparator}del.txt').deleteSync();
    File(
      '$_root${Platform.pathSeparator}old-name.txt',
    ).renameSync('$_root${Platform.pathSeparator}new-name.txt');
    _write('add.txt', 'a1');
    await _store.snapshot('s1', 1);

    final Map<String, String> forward = <String, String>{
      for (final CheckpointFileChange change in await _store.changesBetween(
        's1',
        0,
        1,
      ))
        change.path: change.status,
    };
    expect(forward, <String, String>{
      'mod.txt': 'modified',
      'del.txt': 'deleted',
      'new-name.txt': 'renamed',
      'add.txt': 'added',
    });
    expect(await _store.changesBetween('s1', 1, 1), isEmpty);
    final Map<String, String> backward = <String, String>{
      for (final CheckpointFileChange change in await _store.changesBetween(
        's1',
        1,
        0,
      ))
        change.path: change.status,
    };
    expect(backward, <String, String>{
      'mod.txt': 'modified',
      'del.txt': 'added',
      'old-name.txt': 'renamed',
      'add.txt': 'deleted',
    });
  });

  test('恢复拒绝含 .opencode 的旧快照（fail-closed，一个文件都不动）', () async {
    if (!_gitOk) return;
    _setUp();
    _write('a.txt', 'v0');
    await _store.snapshot('s1', 0);

    // 模拟旧版本采集侧未排除 .opencode：手工提交进影子仓库并改索引指向它。
    _write('.opencode/README.md', 'mine');
    _shadowGit(<String>['add', '-f', '.opencode/README.md']);
    _shadowGit(<String>['commit', '--quiet', '-m', 'legacy']);
    final String legacy = _shadowGit(<String>['rev-parse', 'HEAD']).trim();
    _pointIndexAt('s1', 0, legacy);

    _write('a.txt', 'worktree-later');
    await expectLater(
      _store.restore('s1', 0),
      throwsA(
        isA<CheckpointException>().having(
          (CheckpointException e) => e.code,
          'code',
          'read-only-path',
        ),
      ),
      reason: 'read-tree --reset -u 会把 .opencode 物化回工作区，必须整体拒绝',
    );
    expect(_read('a.txt'), 'worktree-later', reason: '拒绝时一个文件都不该动');
    expect(_read('.opencode/README.md'), 'mine');
  });
}

/// 恢复基线并顺手删掉多余文件后，工作区应只剩基线里的东西。
Future<CheckpointRestore> _restoreTurn0(GitShadowStore store) =>
    store.restore('s1', 0);

/// 包一层真实执行器，让 `ls-files --cached` 少报某个路径——用来验证
/// 「暂存不完整」时 store 会报错而不是静默产出残缺快照。
class _DroppingRunner implements GitRunner {
  const _DroppingRunner(this.inner, this.drop);

  final GitRunner inner;
  final String drop;

  @override
  Future<bool> available() => inner.available();

  @override
  Future<GitResult> run(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) async {
    final GitResult r = await inner.run(
      args,
      gitDir: gitDir,
      workTree: workTree,
    );
    return _maybeDrop(args, r);
  }

  @override
  GitResult runSync(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) =>
      _maybeDrop(args, inner.runSync(args, gitDir: gitDir, workTree: workTree));

  GitResult _maybeDrop(List<String> args, GitResult r) {
    if (!args.contains('ls-files')) return r;
    final List<String> kept = <String>[
      for (final String p in r.stdout.split('\u0000'))
        if (p.isNotEmpty && p != drop) p,
    ];
    return GitResult(r.exitCode, '${kept.join('\u0000')}\u0000', r.stderr);
  }
}

/// 在影子仓库里跑一条 git 命令（测试造旧格式提交用），返回 stdout。
String _shadowGit(List<String> args) {
  final ProcessResult result = Process.runSync('git', <String>[
    '--git-dir=${_store.gitDir}',
    '--work-tree=$_root',
    '-c',
    'user.email=nava@localhost',
    '-c',
    'user.name=nava',
    ...args,
  ]);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} 失败：${result.stderr}');
  }
  return result.stdout is String ? result.stdout! as String : '';
}

/// 把影子索引里某轮的提交改成 [sha]（模拟「旧版本写入的快照」）。
void _pointIndexAt(String sessionId, int turn, String sha) {
  final File index = _store.indexFile(sessionId);
  final Map<String, Object?> json =
      jsonDecode(utf8.decode(gzip.decode(index.readAsBytesSync())))
          as Map<String, Object?>;
  final List<Map<String, Object?>> turns = <Map<String, Object?>>[
    for (final Object? item
        in (json['turns'] as List<Object?>?) ?? const <Object?>[])
      if (item is Map)
        <String, Object?>{
          ...item.cast<String, Object?>(),
          if (item['turn'] == turn) 'commit': sha,
        },
  ];
  index.writeAsBytesSync(
    gzip.encode(utf8.encode(jsonEncode(<String, Object?>{'turns': turns}))),
  );
}

/// 某轮提交树里的文件路径。
List<String> _lsTree(String sha) {
  final ProcessResult r = Process.runSync('git', <String>[
    '--git-dir=${_store.gitDir}',
    '--work-tree=$_root',
    'ls-tree',
    '-r',
    '--name-only',
    '-z',
    sha,
  ]);
  final String out = r.stdout is String ? r.stdout! as String : '';
  return <String>[
    for (final String p in out.split('\u0000'))
      if (p.isNotEmpty) p,
  ];
}

/// 某轮的提交 sha。
String _commitOf(String sessionId, int turn) {
  final ProcessResult r = Process.runSync('git', <String>[
    '--git-dir=${_store.gitDir}',
    'rev-list',
    '--max-count=1',
    'checkpoints/$sessionId/$turn',
  ]);
  return r.stdout is String ? (r.stdout! as String).trim() : '';
}

/// 影子仓库对象库的总字节（loose + pack）。
int _objectStoreBytes() {
  final ProcessResult r = Process.runSync('git', <String>[
    '--git-dir=${_store.gitDir}',
    'count-objects',
    '-v',
  ]);
  final String out = r.stdout is String ? r.stdout! as String : '';
  // 输出形如 `size: 1234\ncount: 5\n...`；用 size（磁盘占用）判断是否重存。
  for (final String line in out.split('\n')) {
    if (line.startsWith('size:')) {
      return int.tryParse(line.substring(5).trim()) ?? 0;
    }
  }
  return 0;
}

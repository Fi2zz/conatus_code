/// 影子仓库式快照存储：把工作区提交进一个独立的 git dir。
///
/// 布局：`<projectDir>/checkpoints/shadow.git`（仓库）+ 每会话一个索引
/// `shadow-index/<sessionId>`（gzip JSON，轮次 → 提交 sha，见
/// `shadow_index.dart`）。git dir 本身在排除区里，不会自噬。
///
/// 相对自研归档（`ArchiveCheckpointStore`）的取舍：
///
/// - **快**：内容寻址 + zlib + 增量全由 git 提供。同一文件改 N 次只存 N
///   份 blob（归档实现每个版本各存一份完整内容），且对象跨会话复用——
///   第二次打开会话不再重付全量代价（894MB 工作区首次约 20s，之后近乎为 0）。
/// - **依赖 git 二进制**：无 git 时不可用，由装配层降级回归档实现。
/// - **不要求工作区是仓库**：影子 git dir 与用户仓库完全解耦，实测用户
///   仓库的 `status` / `log` 不受影子提交影响。这正是选影子而非用户仓库
///   的理由——agent 的 wip 提交不该混进用户历史。
///
/// 与归档实现共享的语义（见 `CheckpointStore`）：rsync 式恢复、符号链接
/// 不进快照、恢复前 fail-closed 越界校验、`projectDir` 与 `ignore` 排除。
library;

import 'dart:io';

import 'checkpoint_paths.dart';
import 'checkpoint_scan.dart';
import 'checkpoint_store.dart';
import 'checkpoint_types.dart';
import 'shadow_git_runner.dart';
import 'shadow_index.dart';

/// 影子仓库式快照存储。
class GitShadowStore implements CheckpointStore {
  GitShadowStore({
    required String root,
    required this.projectDir,
    this.keep = 5,
    this.ignore = const <String>[],
    GitRunner? git,
  }) : root = Directory(root).absolute.path,
       _git = git ?? const ProcessGitRunner();

  @override
  final String root;

  @override
  final String projectDir;

  @override
  final int keep;

  @override
  final List<String> ignore;

  final GitRunner _git;

  /// 影子仓库目录（[projectDir] 下的 `checkpoints/shadow.git`）。
  ///
  /// 保持在 `projectDir` 内而非工作区根下：`projectDir` 整树已被
  /// `kCheckpointDefaultIgnores` 之外的 `projectDir` 规则排除（见
  /// `_writeExcludes`），故影子仓库自身不会被 `add --all` 卷进快照——
  /// 这点由 `排除项` 用例守住。路径必须**规范化**（无 `..`）：git 要求
  /// `--git-dir` 与 `--work-tree` 不互相包含，带 `..` 会直接报 fatal。
  String get gitDir =>
      Directory(sessionRoot()).absolute.path +
      Platform.pathSeparator +
      _shadowDirName;

  /// 影子仓库目录名。
  static const String _shadowDirName = 'shadow.git';

  /// 检查点根目录（会话索引所在；与影子仓库同级）。
  String sessionRoot() => '$projectDir${Platform.pathSeparator}checkpoints';

  /// 某会话的索引文件。
  File indexFile(String sessionId) => File(
    '${sessionRoot()}${Platform.pathSeparator}shadow-index'
    '${Platform.pathSeparator}$sessionId',
  );

  /// 环境里是否有可用 git；装配层据此决定用本实现还是归档实现。
  Future<bool> gitAvailable() => _git.available();

  // ---- 存储契约 -------------------------------------------------------

  @override
  Future<void> clearSession(String sessionId) async {
    final List<ShadowCheckpointRef> refs = _refs(sessionId);
    for (final ShadowCheckpointRef ref in refs) {
      await _gitObj(<String>['tag', '-d', _tag(sessionId, ref.turn)]);
    }
    // 索引连同它独占的提交一起清；对象留着（可能被别的会话/轮次引用，
    // 清了要重写可达性，收益不抵风险）。
    final File index = indexFile(sessionId);
    if (index.existsSync()) await index.delete();
  }

  @override
  Future<void> snapshot(
    String sessionId,
    int turn, {
    String? lastEventId,
  }) async {
    await _ensureRepo();
    await _stageWorktree();
    final GitResult commit = await _gitObj(<String>[
      'commit',
      '--allow-empty',
      '--quiet',
      '-m',
      'turn $turn${lastEventId == null ? '' : ' $lastEventId'}',
    ]);
    _expect(commit, '提交影子快照');
    final String sha = _headSha();
    final String tag = _tag(sessionId, turn);
    await _gitObj(<String>['tag', '--force', tag, sha]);
    await _gitObj(<String>[
      'update-ref',
      'refs/checkpoints/$sessionId/$turn',
      sha,
    ]);
    _upsert(
      sessionId,
      ShadowCheckpointRef(
        turn: turn,
        commit: sha,
        files: _fileCount(sha),
        lastEventId: lastEventId,
      ),
    );
    prune(sessionId);
  }

  @override
  List<CheckpointInfo> list(String sessionId) => <CheckpointInfo>[
    for (final ShadowCheckpointRef ref in _refs(sessionId))
      CheckpointInfo(turn: ref.turn, files: ref.files),
  ];

  @override
  List<int> turnsOf(String sessionId) => <int>[
    for (final ShadowCheckpointRef r in _refs(sessionId)) r.turn,
  ];

  @override
  Future<CheckpointManifest> loadManifest(String sessionId, int turn) async {
    final List<ShadowCheckpointRef> refs = _refs(sessionId);
    for (final ShadowCheckpointRef ref in refs) {
      if (ref.turn == turn) return ref.toManifest();
    }
    throw CheckpointException(
      'missing-manifest',
      '检查点 $turn 缺少清单（会话 $sessionId）',
    );
  }

  @override
  Future<CheckpointRestore> restore(String sessionId, int turn) async {
    final String? sha = _commitOf(sessionId, turn);
    if (sha == null) {
      throw const CheckpointException('missing-checkpoint', '检查点不存在');
    }
    final List<String> paths = _lsTree(sha);
    // fail-closed：先校验全部路径（目标态 + 将被删除的当前文件），
    // 任何越界都在改动一个文件之前抛。
    ensurePathsRestorable(root, paths);
    final Set<String> target = paths.toSet();
    final int removed = await _deleteExtras(target);
    // `read-tree --reset -u` 把工作区精确重置到该提交（含删除之后新增的
    // 文件）。`checkout <sha> -- .` 做不到删除，故不用。
    final GitResult reset = await _gitObj(<String>[
      'read-tree',
      '--reset',
      '-u',
      sha,
    ]);
    _expect(reset, '恢复工作区');
    return CheckpointRestore(restored: paths.length, deleted: removed);
  }

  @override
  void prune(String sessionId) {
    if (keep <= 0) return;
    final List<ShadowCheckpointRef> refs = _refs(sessionId);
    final List<ShadowCheckpointRef> deltas = refs
        .where((ShadowCheckpointRef r) => r.turn > 0)
        .toList();
    final int excess = deltas.length - (keep - 1);
    if (excess <= 0) return;
    for (int i = 0; i < excess; i++) {
      _gitObjSync(<String>['tag', '-d', _tag(sessionId, deltas[i].turn)]);
      _gitObjSync(<String>[
        'update-ref',
        '-d',
        'refs/checkpoints/$sessionId/${deltas[i].turn}',
      ]);
    }
    writeShadowIndex(indexFile(sessionId), <ShadowCheckpointRef>[
      ...refs.where((ShadowCheckpointRef r) => r.turn == 0),
      ...deltas.sublist(excess),
    ]);
  }

  // ---- git 内部操作 ---------------------------------------------------

  /// 单次 `git add` 传多少路径（argv 长度上限的保守取值）。
  static const int _addBatchSize = 400;

  /// 把工作区当前状态暂存进影子仓库的索引。
  ///
  /// **不用 `git add --all`**：那会让 git 顺从工作区的 `.gitignore`
  /// （Swift 项目的 `.build/`、前端项目的 `dist/` 都在里面），而归档实现
  /// 只认 `kCheckpointDefaultIgnores` + 用户 `ignore`。两者一旦不一致，
  /// 恢复时的 rsync 删除就会按残缺清单把文件删掉——实测在 9661 文件的
  /// swiftus 工作区上，影子快照只收了 293 个，恢复删掉了其余 9119 个。
  ///
  /// 故排除判定完全由我们自己做（[checkpointWalk]，与归档实现同一份
  /// 代码），再把结果**显式路径**喂给 `git add -f`：`-f` 覆盖 ignore
  /// 规则，既然只传我们想要的，结果就等于自定义排除面。分批是因为 argv
  /// 长度有限。
  Future<void> _stageWorktree() async {
    final List<String> wanted = await _walkPaths();
    for (final List<String> batch in _batched(wanted)) {
      _expect(await _gitObj(<String>['add', '-f', '--', ...batch]), '暂存工作区');
    }
    // 删除：已跟踪但磁盘上已不存在的路径要显式从索引摘掉。`git add` 只处理
    // 「传进去的路径」，看不到这些——不摘的话本轮会把它们当成还在。
    for (final List<String> batch in _batched(_trackedButGone())) {
      _expect(
        await _gitObj(<String>[
          'rm',
          '--cached',
          '--quiet',
          '--ignore-unmatch',
          '--',
          ...batch,
        ]),
        '记录已删除的文件',
      );
    }
  }

  /// 自己 walk 出来的应入快照路径（与归档实现同一套排除判定）。
  Future<List<String>> _walkPaths() async {
    final List<String> paths = <String>[];
    await for (final FileSystemEntity entity in checkpointWalk(
      root,
      projectRel,
      ignore,
    )) {
      paths.add(checkpointRelativeTo(entity, root));
    }
    return paths;
  }

  /// 已被影子仓库跟踪、但当前工作区已不存在的路径。
  List<String> _trackedButGone() {
    final GitResult tracked = _gitObjSync(<String>[
      'ls-files',
      '-z',
      '--cached',
    ]);
    if (!tracked.ok) return const <String>[];
    return <String>[
      for (final String rel in tracked.stdout.split('\u0000'))
        if (rel.isNotEmpty &&
            !File('$root${Platform.pathSeparator}$rel').existsSync())
          rel,
    ];
  }

  /// 把路径切成不超过 [_addBatchSize] 的批。
  static Iterable<List<String>> _batched(List<String> paths) sync* {
    for (int i = 0; i < paths.length; i += _addBatchSize) {
      yield paths.sublist(
        i,
        i + _addBatchSize > paths.length ? paths.length : i + _addBatchSize,
      );
    }
  }

  /// 确保影子仓库已初始化，并把排除项写进 `.git/info/exclude`。
  Future<void> _ensureRepo() async {
    if (!Directory(gitDir).existsSync()) {
      // git init 要求 --git-dir 的**父目录**已存在（否则报
      // `Invalid path ... No such file or directory`）。
      Directory(gitDir).parent.createSync(recursive: true);
      final GitResult init = await _gitObj(<String>['init', '--quiet']);
      _expect(init, '初始化影子仓库');
    }
    await _writeExcludes();
  }

  /// 写排除规则：`.git`、内置默认项、`projectDir` 整树、用户 `ignore`。
  ///
  /// 写进 `.git/info/exclude` 而非工作区的 `.gitignore`——后者会被当作
  /// 快照内容提交进去，且会污染用户项目。
  Future<void> _writeExcludes() async {
    final File file = File(
      '$gitDir${Platform.pathSeparator}info'
      '${Platform.pathSeparator}exclude',
    );
    final String body = <String>[
      '# nava 检查点影子仓库的排除项（勿手改：每次快照前重写）',
      for (final String prefix in kCheckpointDefaultIgnores) '$prefix/',
      if (projectRel.isNotEmpty) '${projectRel.replaceAll('\\', '/')}/',
      for (final String prefix in ignore)
        '${prefix.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '')}/',
      '',
    ].join('\n');
    file.parent.createSync(recursive: true);
    await file.writeAsString(body, flush: true);
  }

  /// 当前 HEAD 的提交 sha（短 sha 够用：只在本仓库内比对）。
  String _headSha() {
    final GitResult result = _gitObjSync(<String>['rev-parse', 'HEAD']);
    _expect(result, '读取 HEAD');
    return result.stdout.trim();
  }

  /// 该提交树里的文件数（`git ls-tree -r` 计数，供列表展示）。
  int _fileCount(String sha) => _lsTree(sha).length;

  /// 该提交树里的全部文件路径（相对工作区根）。
  List<String> _lsTree(String sha) {
    final GitResult result = _gitObjSync(<String>[
      'ls-tree',
      '-r',
      '--name-only',
      '-z',
      sha,
    ]);
    _expect(result, '读取提交树');
    return <String>[
      for (final String path in result.stdout.split('\u0000'))
        if (path.isNotEmpty) path,
    ];
  }

  /// 删除当前工作区中「不在目标态、且未被排除」的文件；返回删除数。
  ///
  /// 排除项必须跳过：影子 git dir 就在 `projectDir` 下，删掉它等于自毁。
  Future<int> _deleteExtras(Set<String> target) async {
    final List<String> extras = <String>[];
    await for (final FileSystemEntity entity in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final String rel = checkpointRelativeTo(entity, root);
      if (checkpointExcluded(rel, projectRel, ignore)) continue;
      if (target.contains(rel)) continue;
      extras.add(rel);
    }
    for (final String rel in extras) {
      // 防御性：extras 本体不是链接（list 用 followLinks:false），父链仍可能是。
      ensureRestorable(root, rel);
      File('$root${Platform.pathSeparator}$rel').deleteSync();
    }
    return extras.length;
  }

  // ---- 索引 -----------------------------------------------------------

  List<ShadowCheckpointRef> _refs(String sessionId) =>
      readShadowIndex(indexFile(sessionId));

  String? _commitOf(String sessionId, int turn) {
    for (final ShadowCheckpointRef ref in _refs(sessionId)) {
      if (ref.turn == turn) return ref.commit;
    }
    return null;
  }

  void _upsert(String sessionId, ShadowCheckpointRef ref) {
    writeShadowIndex(indexFile(sessionId), <ShadowCheckpointRef>[
      for (final ShadowCheckpointRef old in _refs(sessionId))
        if (old.turn != ref.turn) old,
      ref,
    ]);
  }

  /// 会话 + 轮次的 tag 名（不可读名不适用于 git：tag 本就可见，
  /// 但用 `refs/checkpoints/` 前缀把检查点与用户分支隔开）。
  String _tag(String sessionId, int turn) => 'checkpoints/$sessionId/$turn';

  /// `projectDir` 相对 [root] 的路径（排除按相对路径比较）。
  String get projectRel {
    final String sep = Platform.pathSeparator;
    final String absRoot = root.endsWith(sep) ? root : '$root$sep';
    if (projectDir.startsWith(absRoot)) {
      return projectDir.substring(absRoot.length);
    }
    return projectDir;
  }

  // ---- 执行 -----------------------------------------------------------

  Future<GitResult> _gitObj(List<String> args) =>
      _git.run(args, gitDir: gitDir, workTree: root);

  /// 同步版（`list`/`prune` 这类同步接口用；会阻塞事件循环，故只用于
  /// 低频路径）。
  GitResult _gitObjSync(List<String> args) {
    final GitRunner runner = _git;
    if (runner is ProcessGitRunner) {
      return runner.runSync(args, gitDir: gitDir, workTree: root);
    }
    throw const CheckpointException(
      'no-sync-runner',
      '影子仓库同步路径需要 ProcessGitRunner',
    );
  }

  /// git 失败转成 [CheckpointException]（编排层转成提示，不打断轮次）。
  void _expect(GitResult result, String what) {
    if (result.ok) return;
    final String detail = result.stderr.trim().isEmpty
        ? '退出码 ${result.exitCode}'
        : result.stderr.trim();
    throw CheckpointException('git-failed', '$what 失败：$detail');
  }
}

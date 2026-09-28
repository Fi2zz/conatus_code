// 在指定工作区上跑影子快照 / 恢复，核对存储层行为（不经 TUI）。
//
// ⚠️ 只接受 /tmp 下的工作区。恢复是 rsync 语义（会删文件），本脚本早前身
// 接受任意路径，曾把真实项目的 9661 个文件删到只剩 293 个。
//
// 用法：
//   dart run tool/play.dart survey   <workdir>
//   dart run tool/play.dart snapshot <workdir> <dataDir> <session> <turn>
//   dart run tool/play.dart restore  <workdir> <dataDir> <session> <turn>
//   dart run tool/play.dart ls       <workdir> <dataDir> <session>
//   dart run tool/play.dart lsTree   <workdir> <dataDir> <session> <turn>
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';

const String _tmpRoot = '/tmp';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stdout.writeln(
      '用法: play.dart <survey|snapshot|restore|ls|lsTree> <workdir> ...',
    );
    exit(1);
  }
  final String root = Directory(args[1]).absolute.path;
  _guard(root);
  final String cmd = args.first;
  final String dataDir = args.length > 2 ? args[2] : '/tmp/nava-play-data';
  final String session = args.length > 3 ? args[3] : 's1';
  final int turn = args.length > 4 ? int.parse(args[4]) : 0;

  switch (cmd) {
    case 'survey':
      await survey(root);
    case 'snapshot':
      await doSnapshot(root, dataDir, session, turn);
    case 'restore':
      await doRestore(root, dataDir, session, turn);
    case 'ls':
      listTurns(root, dataDir, session);
    case 'lsTree':
      listTree(root, dataDir, session, turn);
    default:
      stdout.writeln('未知命令: $cmd');
  }
}

/// 硬性防护：只允许 /tmp 下的工作区。
void _guard(String root) {
  if (!root.startsWith(_tmpRoot)) {
    stderr.writeln('拒绝：只允许 /tmp 下的工作区（当前 $root）');
    stderr.writeln('恢复会删文件，别拿真实项目试。');
    exit(2);
  }
}

GitShadowStore openStore(String root, String dataDir) =>
    GitShadowStore(root: root, projectDir: dataDir);

/// 勘察：conatus 口径 vs git 口径，各收哪些文件。
Future<void> survey(String root) async {
  const String projectRel = 'nava-probe'; // 探测用，不匹配任何真实路径
  final List<String> conatus = <String>[];
  int bytes = 0;
  await for (final FileSystemEntity e in checkpointWalk(
    root,
    projectRel,
    const <String>[],
  )) {
    final String rel = checkpointRelativeTo(e, root);
    conatus.add(rel);
    bytes += (e as File).lengthSync();
  }
  stdout.writeln(
    'conatus 口径：${conatus.length} 个文件 / '
    '${(bytes / 1048576).toStringAsFixed(1)}MB',
  );

  final ProcessResult r = Process.runSync('git', <String>[
    '-C',
    root,
    '-c',
    'core.quotepath=false',
    'ls-files',
  ]);
  final List<String> tracked = r.stdout is String
      ? (r.stdout! as String)
            .split('\n')
            .where((String l) => l.trim().isNotEmpty)
            .toList()
      : <String>[];
  stdout.writeln('git 已跟踪：${tracked.length} 个（影子实现不参考它）');

  // git 忽略但 conatus 会收的（.gitignore 与 conatus 排除面的差集）
  final ProcessResult ign = Process.runSync('git', <String>[
    '-C',
    root,
    'status',
    '--porcelain',
    '--ignored',
    '--untracked-files=all',
  ]);
  final String ignOut = ign.stdout is String ? ign.stdout! as String : '';
  final List<String> ignored = <String>[
    for (final String line in ignOut.split('\n'))
      if (line.startsWith('!! ')) line.substring(3).trim(),
  ];
  final Set<String> conatusSet = conatus.toSet();
  final List<String> onlyConatus = <String>[
    for (final String p in ignored)
      if (conatusSet.contains(p)) p,
  ];
  stdout.writeln('\ngit 忽略、但 conatus 会收：${onlyConatus.length} 个');
  for (final String p in onlyConatus.take(15)) {
    stdout.writeln('  $p');
  }
  if (onlyConatus.length > 15) {
    stdout.writeln('  ... 还有 ${onlyConatus.length - 15} 个');
  }

  // 嵌套 git 仓库：conatus 的 `.git` 排除是顶层前缀匹配，嵌在子目录的
  // .git 不会被排除。
  final List<String> nested = <String>[
    for (final String p in conatus)
      if (p == '.git' || p.endsWith('/.git') || p.contains('/.git/')) p,
  ];
  stdout.writeln('\n⚠ 会进快照的嵌套 .git 内容：${nested.length} 个路径');
  for (final String p in nested.take(8)) {
    stdout.writeln('  $p');
  }
  if (nested.length > 8) stdout.writeln('  ... 还有 ${nested.length - 8} 个');
}

Future<void> doSnapshot(
  String root,
  String dataDir,
  String session,
  int turn,
) async {
  final GitShadowStore store = openStore(root, dataDir);
  final Stopwatch w = Stopwatch()..start();
  await store.snapshot(session, turn);
  w.stop();
  stdout.writeln('快照 $session turn $turn：${w.elapsedMilliseconds}ms');
  listTurns(root, dataDir, session);
}

Future<void> doRestore(
  String root,
  String dataDir,
  String session,
  int turn,
) async {
  final GitShadowStore store = openStore(root, dataDir);
  final Stopwatch w = Stopwatch()..start();
  final CheckpointRestore r = await store.restore(session, turn);
  w.stop();
  stdout.writeln(
    '恢复到 turn $turn：${w.elapsedMilliseconds}ms  '
    '还原 ${r.restored} / 删除 ${r.deleted}',
  );
}

void listTurns(String root, String dataDir, String session) {
  final GitShadowStore store = openStore(root, dataDir);
  for (final CheckpointInfo i in store.list(session)) {
    stdout.writeln('turn ${i.turn}  文件 ${i.files}');
  }
}

/// 列出某轮提交树里的全部路径（核对快照收得对不对）。
void listTree(String root, String dataDir, String session, int turn) {
  final GitShadowStore store = openStore(root, dataDir);
  final ProcessResult r = Process.runSync('git', <String>[
    '--git-dir=${store.gitDir}',
    'ls-tree',
    '-r',
    '--name-only',
    '-z',
    'checkpoints/$session/$turn',
  ]);
  final String out = r.stdout is String ? r.stdout! as String : '';
  for (final String p in out.split('\u0000')) {
    if (p.isNotEmpty) stdout.writeln(p);
  }
}

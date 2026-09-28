// 影子 git 仓库 vs 自研归档：同一工作区上对比 turn 0 首次、turn 1、以及
// **新会话 turn 0**（对象复用能否免掉全量重拍）的耗时与占用。
//
// ⚠️ 只在**临时目录**里跑合成工作区。恢复是 rsync 语义（会删文件），拿真实
// 项目当样本会删数据——本脚本曾因此把 swiftus 的 9661 个文件删到只剩 293
// 个。故这里不接受任何外部路径参数。
//
// 用法：dart run tool/bench_shadow.dart [文件数=2000] [单文件KB=64]
import 'dart:io';
import 'dart:math';

import 'package:conatus_code/conatus_code.dart';

Future<void> main(List<String> args) async {
  final int fileCount = args.isEmpty ? 2000 : int.parse(args.first);
  final int fileKb = args.length < 2 ? 64 : int.parse(args[1]);

  final Directory ws = Directory.systemTemp.createTempSync('nava-bench-ws');
  final Directory shadowData = Directory.systemTemp.createTempSync(
    'nava-bench-git',
  );
  final Directory archData = Directory.systemTemp.createTempSync(
    'nava-bench-arch',
  );
  final String root = ws.path;

  // 合成工作区。每个文件内容必须**各不相同**——早先所有文件共用同一段
  // chunk，git 按内容寻址把 125MB 压成了一个 blob（884KB），测出来的数毫
  // 无意义。这里每文件独立种子 + 可压缩的文本状结构，逼近真实源码的压缩率。
  final int perFile = fileKb * 1024;
  for (int i = 0; i < fileCount; i++) {
    final String rel = 'src/mod${i % 200}/file${i ~/ 200}_$i.dart';
    final File f = File('$root${Platform.pathSeparator}$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(_makeText(Random(42 + i), perFile, i));
  }
  stdout.writeln(
    '合成工作区：$fileCount 文件 / '
    '${(fileCount * perFile / 1048576).toStringAsFixed(1)}MB\n',
  );

  final GitShadowStore shadow = GitShadowStore(
    root: root,
    projectDir: shadowData.path,
  );
  if (!await shadow.gitAvailable()) {
    stdout.writeln('环境无 git，跳过');
    _cleanup(ws, shadowData, archData);
    return;
  }
  final ArchiveCheckpointStore archive = ArchiveCheckpointStore(
    root: root,
    projectDir: archData.path,
  );

  // turn 0
  final int shTurn0 = await _time(() => shadow.snapshot('s1', 0));
  final String shSize0 = _storeSize(shadow);
  final int arTurn0 = await _time(() => archive.snapshot('a1', 0));

  // turn 1：只改一个文件
  File('$root${Platform.pathSeparator}probe.txt').writeAsStringSync('turn 1');
  final int shTurn1 = await _time(() => shadow.snapshot('s1', 1));
  final String shSize1 = _storeSize(shadow);
  final int arTurn1 = await _time(() => archive.snapshot('a1', 1));
  final String arSize1 = _dirSize(archData);

  // 新会话 turn 0：内容与上一条时间线相同
  final int shNew = await _time(() => shadow.snapshot('s2', 0));
  final int arNew = await _time(() => archive.snapshot('a2', 0));

  stdout.writeln(
    '              ${'影子 git'.padRight(12)}${'自研归档'.padRight(12)}',
  );
  stdout.writeln(
    'turn 0 首次     ${_ms(shTurn0).padRight(12)}${_ms(arTurn0).padRight(12)}',
  );
  stdout.writeln(
    'turn 1 改1文件  ${_ms(shTurn1).padRight(12)}${_ms(arTurn1).padRight(12)}',
  );
  stdout.writeln(
    '新会话 turn 0   ${_ms(shNew).padRight(12)}${_ms(arNew).padRight(12)}'
    '   <-- 归档在此全量重拍',
  );
  stdout.writeln('\n占用（turn 0 / 两轮后）');
  stdout.writeln('  影子  $shSize0 / $shSize1');
  stdout.writeln('  归档  ${_dirSize(archData)} / $arSize1');

  // 恢复（只在合成工作区里做）
  final CheckpointRestore back = await shadow.restore('s1', 0);
  stdout.writeln(
    '\n影子恢复到 turn 0：还原 ${back.restored} / 删除 ${back.deleted}'
    '（删的正是 turn 1 加的 probe.txt）',
  );
  _cleanup(ws, shadowData, archData);
}

Future<int> _time(Future<void> Function() action) async {
  final Stopwatch w = Stopwatch()..start();
  await action();
  w.stop();
  return w.elapsedMilliseconds;
}

String _ms(int value) =>
    value >= 1000 ? '${(value / 1000).toStringAsFixed(2)}s' : '${value}ms';

/// 造一段「像源码」的可压缩文本，约 [bytes] 字节，混入 [salt] 使各文件不同。
String _makeText(Random random, int bytes, int salt) {
  const String words =
      'the quick brown fox jumps over lazy dog import export class void final '
      'return if else while for await async stream future widget build '
      'context render frame buffer commit repository branch checkout diff';
  final List<String> tokens = words.split(' ');
  final StringBuffer out = StringBuffer();
  int state = (random.nextInt(1 << 30) ^ (salt * 2654435761)) & 0x7fffffff;
  while (out.length < bytes) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    out.write(tokens[state % tokens.length]);
    out.write(state % 17 == 0 ? '\n' : ' ');
  }
  return out.toString().substring(0, bytes);
}

void _cleanup(Directory ws, Directory data, Directory extra) {
  for (final Directory dir in <Directory>[ws, data, extra]) {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// 影子仓库对象库占用。
String _storeSize(GitShadowStore store) {
  final ProcessResult r = Process.runSync('git', <String>[
    '--git-dir=${store.gitDir}',
    'count-objects',
    '-vH',
  ]);
  final String out = r.stdout is String ? r.stdout! as String : '';
  for (final String line in out.split('\n')) {
    if (line.startsWith('size-pack:') || line.startsWith('size:')) {
      return line.split(':').last.trim();
    }
  }
  return '?';
}

/// 目录占用（递归，MiB）。
String _dirSize(Directory dir) {
  if (!dir.existsSync()) return '0';
  final ProcessResult r = Process.runSync('du', <String>['-shm', dir.path]);
  final String out = r.stdout is String ? r.stdout! as String : '';
  return out.split('\t').first.trim();
}

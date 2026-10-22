/// 工作区的 git 差异（`/diff` 的 `working` 范围）：已跟踪改动 + 未跟踪文件。
///
/// 只读：只跑 `git diff` / `git ls-files` 与读文件；不在 git 仓库内返回
/// `null`，由调用方回落到轮次差异。
library;

import 'dart:convert';
import 'dart:io';

import 'diff_model.dart';
import 'diff_parser.dart';

/// 工作区差异采集器。
class WorkingDiff {
  const WorkingDiff(this.workdir);

  /// 工作区根（绝对路径）。
  final String workdir;

  /// 采集差异；不在 git 仓库内（或 git 不可用）返回 `null`。
  Future<List<FileDiff>?> load() async {
    if (!await _insideGitRepo()) return null;
    final ProcessResult result = await Process.run('git', <String>[
      'diff',
      '--no-ext-diff',
      '--unified=3',
    ], workingDirectory: workdir);
    if (result.exitCode != 0) return null;
    final List<FileDiff> diffs = <FileDiff>[
      for (final FileDiff diff in parseUnifiedDiff(result.stdout.toString()))
        if (showsDiffPath(diff.path)) diff,
      ...await _untrackedDiffs(),
    ];
    diffs.sort((FileDiff a, FileDiff b) => a.path.compareTo(b.path));
    return diffs;
  }

  Future<bool> _insideGitRepo() async {
    try {
      final ProcessResult result = await Process.run('git', <String>[
        'rev-parse',
        '--is-inside-work-tree',
      ], workingDirectory: workdir);
      return result.exitCode == 0 && result.stdout.toString().trim() == 'true';
    } on ProcessException {
      return false;
    }
  }

  /// 未跟踪文件按新增处理（`--exclude-standard` 尊重 `.gitignore`）。
  Future<List<FileDiff>> _untrackedDiffs() async {
    final ProcessResult result = await Process.run('git', <String>[
      'ls-files',
      '--others',
      '--exclude-standard',
      '-z',
    ], workingDirectory: workdir);
    if (result.exitCode != 0) return const <FileDiff>[];
    final List<FileDiff> diffs = <FileDiff>[];
    for (final String path in result.stdout.toString().split('\u0000')) {
      if (path.isEmpty || !showsDiffPath(path)) continue;
      final FileDiff? diff = await _untracked(path);
      if (diff != null) diffs.add(diff);
    }
    return diffs;
  }

  Future<FileDiff?> _untracked(String path) async {
    final List<int> bytes;
    try {
      bytes = await File(_absolute(path)).readAsBytes();
    } on FileSystemException {
      return null;
    }
    final List<FileDiff> diffs = diffLines(
      path,
      null,
      utf8.decode(bytes, allowMalformed: true),
    );
    return diffs.isEmpty ? null : diffs.single;
  }

  String _absolute(String rel) =>
      '$workdir${Platform.pathSeparator}'
      '${rel.replaceAll('/', Platform.pathSeparator)}';
}

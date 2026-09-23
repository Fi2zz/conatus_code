/// 状态栏右侧信息：工作目录（~ 缩写）+ git 分支，与上下文用量的格式化。
library;

import 'dart:io';

/// 解析状态栏位置信息：`~/REPO/conatus master`；非 git 仓库只显示目录。
Future<String> resolveWorkspaceLocation() async {
  final String cwd = _shortenHome(Directory.current.path);
  final String? branch = await _gitBranch(Directory.current.path);
  return branch == null ? cwd : '$cwd $branch';
}

/// 格式化上下文用量：`ctx 299k/1M (30%)`；[maxTokens] 为 0（未知窗口）时
/// 只显示估算值。口径是 chars/4 粗估，只作展示不用于计费。
String formatContextUsage(int tokens, int maxTokens) {
  final String used = _compact(tokens);
  if (maxTokens <= 0) {
    return 'ctx $used';
  }
  final int percent = (tokens * 100 / maxTokens).round().clamp(0, 100);
  return 'ctx $used/${_compact(maxTokens)} ($percent%)';
}

String _shortenHome(String path) {
  final String? home = Platform.environment['HOME'];
  if (home == null) {
    return path;
  }
  if (path == home || path.startsWith('$home/')) {
    return '~${path.substring(home.length)}';
  }
  return path;
}

Future<String?> _gitBranch(String cwd) async {
  try {
    final ProcessResult result = await Process.run(
      'git',
      const <String>['rev-parse', '--abbrev-ref', 'HEAD'],
      workingDirectory: cwd,
    ).timeout(const Duration(seconds: 2));
    if (result.exitCode != 0) {
      return null;
    }
    final String branch = (result.stdout as String).trim();
    return branch.isEmpty || branch == 'HEAD' ? null : branch;
  } on Object {
    return null; // 非 git 环境 / git 缺失：位置信息只显示目录。
  }
}

String _compact(int tokens) {
  if (tokens < 1000) {
    return '${tokens}t';
  }
  if (tokens < 1000000) {
    return '${(tokens / 1000).round()}k';
  }
  return '${(tokens / 1000000).round()}M';
}

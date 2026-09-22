/// launcher 进程的拼参与流采集工具（内部实现，不对外导出）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'sandboxed_shell_process.dart';

/// launcher 参数集合。
class LauncherArgSet {
  const LauncherArgSet({
    required this.id,
    required this.root,
    required this.command,
    required this.workdir,
    required this.networkAllowed,
  });

  final String id;
  final String root;
  final String command;
  final String workdir;
  final bool networkAllowed;
}

/// 拼 launcher 参数；cwd 与 root 相同、网络放行时省略对应旗标。
List<String> buildLauncherArgs(LauncherArgSet args) {
  final List<String> result = <String>[
    '--id',
    args.id,
    '--workspace',
    args.root,
    '--sandbox',
  ];
  if (!args.networkAllowed) result.add('--no-net');
  if (args.workdir != args.root) {
    result.addAll(<String>['--cwd', args.workdir]);
  }
  result.addAll(<String>['--', '/bin/sh', '-c', args.command]);
  return result;
}

/// 唯一运行 id。
String runId() => 'cc-${DateTime.now().microsecondsSinceEpoch}';

/// 默认最小环境：拷贝父进程常用键（launcher 侧 env_clear 后沙箱内命令只会
/// 看到这些）。
Map<String, String> defaultMinimalEnv() {
  const List<String> keys = <String>[
    'PATH', 'HOME', 'LANG', 'TERM', 'TMPDIR', 'PUB_CACHE', 'DART_SDK',
  ];
  return <String, String>{
    for (final String key in keys)
      if (Platform.environment[key] != null) key: Platform.environment[key]!,
  };
}

void closeStdin(Process process, String? input) {
  if (input == null) {
    unawaited(process.stdin.close());
    return;
  }
  process.stdin.write(input);
  unawaited(process.stdin.close());
}

/// 采集 stdout/stderr，超上限截断。
Future<CollectedOutput> collectOutput(
    Stream<List<int>> stream, int maxBytes) async {
  final List<int> bytes = <int>[];
  bool truncated = false;
  await for (final List<int> chunk in stream) {
    truncated = appendBytes(bytes, chunk, maxBytes) || truncated;
  }
  return CollectedOutput(
    text: utf8.decode(bytes, allowMalformed: true),
    truncated: truncated,
  );
}

/// 采集 stderr 并剥离 launcher 日志行。
Future<CollectedOutput> collectStripped(
    Stream<List<int>> stream, int maxBytes) async {
  final CollectedOutput raw = await collectOutput(stream, maxBytes);
  return CollectedOutput(
    text: stripLauncherLines(raw.text),
    truncated: raw.truncated,
  );
}

/// 先 SIGTERM（launcher 会杀子进程），250ms 后补 SIGKILL。
void killGracefully(Process process) {
  process.kill();
  Timer(const Duration(milliseconds: 250), () {
    process.kill(ProcessSignal.sigkill);
  });
}

/// 拒绝结果：不抛异常，exitCode 为 null（调用方按非零处理并看到理由）。
ShellRunResult rejected(String message, ShellExecSpec spec) => ShellRunResult(
      exitCode: null,
      timedOut: false,
      timeoutMs: spec.timeoutMs,
      stdout: const CollectedOutput(text: ''),
      stderr: CollectedOutput(text: message),
    );

/// 相对工作目录基于沙箱根解析为绝对路径。
String absoluteWorkdir(String root, String workdir) {
  if (workdir.startsWith('/')) return normalizePath(workdir);
  return normalizePath('$root/$workdir');
}

/// 路径是否在 [root] 之内（含自身）。
bool withinRoot(String path, String root) {
  final String normalized = normalizePath(path);
  return normalized == root || normalized.startsWith('$root/');
}

String normalizePath(String path) =>
    Uri.file(path).normalizePath().toFilePath();

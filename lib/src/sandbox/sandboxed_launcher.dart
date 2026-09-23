/// sandbox-exec 子进程的环境与流采集工具（内部实现，不对外导出）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

/// 把 [chunk] 追加到 [bytes]，超过 [maxBytes] 时截断并返回是否发生截断。
bool appendBytes(List<int> bytes, List<int> chunk, int maxBytes) {
  if (bytes.length >= maxBytes) return true;
  final int remaining = maxBytes - bytes.length;
  if (chunk.length <= remaining) {
    bytes.addAll(chunk);
    return false;
  }
  bytes.addAll(chunk.sublist(0, remaining));
  return true;
}

/// 默认最小环境：显式配置优先，否则拷贝父进程常用键（沙箱内命令只会看到这些）。
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

/// 先 SIGTERM（sandbox-exec 会杀子进程树），250ms 后补 SIGKILL。
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

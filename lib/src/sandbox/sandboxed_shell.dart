/// 沙箱化命令执行器：直调系统 sandbox-exec + 自建 Seatbelt profile。
///
/// 与 [LocalShellExecutor] 对齐 [ShellExecutor] 契约：拒绝、超时、后端故障
/// 都以 [ShellRunResult] 正常返回，仅基础设施故障才抛异常。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'command_policy.dart';
import 'sandboxed_launcher.dart';
import 'sandboxed_shell_options.dart';
import 'sandboxed_shell_process.dart';
import 'seatbelt_profile.dart';

/// 沙箱化的 [ShellExecutor]：经 sandbox-exec 执行，命令先经策略裁决。
class SandboxedShellExecutor implements ShellExecutor {
  SandboxedShellExecutor({required SandboxedShellOptions options})
      : _options = options;

  final SandboxedShellOptions _options;

  /// 缺省前台超时（毫秒），与 [LocalShellExecutor] 一致。
  static const int _defaultTimeoutMs = 120000;

  @override
  ShellExecSpec resolve(ShellExecRequest request) {
    final int timeout =
        math.min(request.timeoutMs ?? _defaultTimeoutMs, _options.maxTimeoutMs);
    final int stdoutMax = math.min(
        request.stdoutMaxBytes ?? _options.maxOutputBytes,
        _options.maxOutputBytes);
    return ShellExecSpec(
      command: request.command,
      workdir: request.workdir == null
          ? _options.root
          : absoluteWorkdir(_options.root, request.workdir!),
      timeoutMs: timeout,
      stdoutMaxBytes: stdoutMax,
      stdin: request.stdin,
      env: request.env,
      cancelSignal: request.cancelSignal,
    );
  }

  @override
  Future<ShellRunResult> run(ShellExecSpec spec) async {
    final CommandVerdict verdict = _options.commandPolicy.decide(spec.command);
    if (verdict.decision != CommandDecision.allow) {
      return rejected('命令被拒绝：${verdict.reason}', spec);
    }
    if (!withinRoot(spec.workdir, _options.root)) {
      return rejected('工作目录越界：${spec.workdir}', spec);
    }
    final Process process = await _spawn(spec);
    closeStdin(process, spec.stdin);
    final Future<CollectedOutput> stdout =
        collectOutput(process.stdout, spec.stdoutMaxBytes);
    final Future<CollectedOutput> stderr =
        collectOutput(process.stderr, _options.maxOutputBytes);
    bool timedOut = false;
    final Timer timer = Timer(Duration(milliseconds: spec.timeoutMs), () {
      timedOut = true;
      killGracefully(process);
    });
    final int exitCode = await process.exitCode;
    timer.cancel();
    final CollectedOutput out = await stdout;
    final CollectedOutput err = await stderr;
    return ShellRunResult(
      exitCode: exitCode,
      timedOut: timedOut,
      timeoutMs: spec.timeoutMs,
      stdout: out,
      stderr: err,
    );
  }

  @override
  Future<ShellProcess> start(ShellExecSpec spec) async {
    final CommandVerdict verdict = _options.commandPolicy.decide(spec.command);
    if (verdict.decision != CommandDecision.allow) {
      return RejectedShellProcess(verdict.reason);
    }
    if (!withinRoot(spec.workdir, _options.root)) {
      return RejectedShellProcess('工作目录越界：${spec.workdir}');
    }
    final Process process = await _spawn(spec);
    closeStdin(process, spec.stdin);
    return SandboxedShellProcess(process, _options.maxOutputBytes);
  }

  Future<Process> _spawn(ShellExecSpec spec) {
    final bool networkAllowed = _networkAllowed(spec.command);
    final List<String> writable = _writableRoots();
    final List<String> args = <String>[
      '-p',
      buildSeatbeltProfile(
        networkAllowed: networkAllowed,
        writableCount: writable.length,
      ),
      ...buildSandboxParams(root: _options.root, writablePaths: writable),
      '--',
      '/bin/sh',
      '-c',
      spec.command,
    ];
    return Process.start(
      _options.backend.sandboxExecPath,
      args,
      environment: _minimalEnv(),
      workingDirectory: spec.workdir,
    );
  }

  /// 可写根 = 缺省缓存 ∪ 用户配置的额外可写路径（展开 `~`、相对基于 root）。
  List<String> _writableRoots() {
    final Set<String> paths = defaultWritableCaches();
    final String home = Platform.environment['HOME'] ?? '';
    for (final String raw in _options.writablePaths) {
      paths.add(_resolveWritable(raw, home));
    }
    return paths.toList();
  }

  String _resolveWritable(String raw, String home) {
    if (raw.startsWith('~/')) return normalizePath('$home/${raw.substring(2)}');
    if (raw.startsWith('/')) return normalizePath(raw);
    return normalizePath('${_options.root}/$raw');
  }

  /// 全局放行或命令前缀命中网络白名单即不附加 `(deny network*)`。
  bool _networkAllowed(String command) {
    if (_options.allowNetwork) return true;
    for (final String prefix in _options.networkAllowlist) {
      if (command.startsWith(prefix)) return true;
    }
    return false;
  }

  /// 最小环境：显式配置优先，否则用默认最小集合。
  Map<String, String> _minimalEnv() =>
      _options.minimalEnv ?? defaultMinimalEnv();
}

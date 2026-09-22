/// OS 沙箱后端不可用时的 fail-closed 执行器：所有命令一律拒绝。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'sandboxed_launcher.dart';
import 'sandboxed_shell_process.dart';

/// 命令被拒时的面向用户说明（含关闭路径）。
const String kSandboxUnavailable =
    'OS 沙箱后端不可用（launcher / Rosetta / Seatbelt），命令执行已禁用；'
    '如需关闭请在 config.toml 设置 [sandbox] enabled = false';

/// 沙箱后端不可用时的占位执行器。
///
/// 不启动任何进程，`run` / `start` 一律按拒绝返回。这是 OS 沙箱层的
/// fail-closed 落点——后端不可用时命令执行不可用，而不是降级为裸本地 shell。
class RejectingShellExecutor implements ShellExecutor {
  RejectingShellExecutor(this.reason);

  /// 拒绝理由（面向用户）。
  final String reason;

  @override
  ShellExecSpec resolve(ShellExecRequest request) => ShellExecSpec(
        command: request.command,
        workdir: request.workdir ?? Directory.current.path,
        timeoutMs: request.timeoutMs ?? 120000,
        stdoutMaxBytes: request.stdoutMaxBytes ?? 64000,
        stdin: request.stdin,
        env: request.env,
        cancelSignal: request.cancelSignal,
      );

  @override
  Future<ShellRunResult> run(ShellExecSpec spec) async => rejected(reason, spec);

  @override
  Future<ShellProcess> start(ShellExecSpec spec) async =>
      RejectedShellProcess(reason);
}

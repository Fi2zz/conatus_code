/// 沙箱两层的装配：应用层文件 jail（Layer 1）与 OS 级沙箱（Layer 2）。
///
/// - Layer 1（`SandboxSettings.fsJail`）：`JailedFileSystem`，纯应用层防误操作，
///   不依赖 OS 后端，任何平台可用；
/// - Layer 2（`SandboxSettings.enabled`）：`SandboxedShellExecutor`，直调系统
///   sandbox-exec + 自建 Seatbelt profile；后端（[SandboxBackend]）不可用时
///   fail-closed，注入 [RejectingShellExecutor] 而非降级本地 shell；
///   `preset = danger_full_access` 时显式不注入 OS 沙箱（回本地直执）。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import '../config/config_schema.dart';
import 'command_policy.dart';
import 'jailed_file_system.dart';
import 'rejecting_shell.dart';
import 'sandbox_probe.dart';
import 'sandboxed_shell.dart';
import 'sandboxed_shell_options.dart';

/// 沙箱装配结果：注入 `create` 的 fs / shell 接缝（null = 用本地实现）。
class SandboxLayers {
  const SandboxLayers({this.fs, this.shell});

  final FileSystem? fs;
  final ShellExecutor? shell;
}

/// 组装两层沙箱接缝；[backend] 为已探测到的 OS 后端（null = 不可用/未启用）。
///
/// [root] 应为规范化的沙箱根（resolveSymbolicLinks 后）。
SandboxLayers resolveSandboxLayers({
  required String root,
  required SandboxSettings settings,
  SandboxBackend? backend,
}) {
  final FileSystem? fs =
      settings.fsJail ? JailedFileSystem(root: root) : null;
  if (!settings.enabled) return SandboxLayers(fs: fs);
  if (settings.preset == SandboxPreset.dangerFullAccess) {
    // 显式无 OS 沙箱：shell 为 null 表示回本地直执；Layer 1 与命令策略不受影响。
    return SandboxLayers(fs: fs);
  }
  if (backend == null) {
    return SandboxLayers(fs: fs, shell: RejectingShellExecutor(kSandboxUnavailable));
  }
  final ShellExecutor shell = SandboxedShellExecutor(
    options: SandboxedShellOptions(
      backend: backend,
      root: root,
      commandPolicy: CommandPolicy(
        root: root,
        allowedExecutables: resolveAllowedExecutables(settings.allowedExecutables),
        readAllowedPaths: resolveReadAllowedPaths(settings.writablePaths),
      ),
      allowNetwork: settings.allowNetwork,
      writablePaths: settings.writablePaths.toSet(),
      networkAllowlist: settings.networkAllowlist.toSet(),
      maxOutputBytes: settings.maxOutputBytes,
      maxTimeoutMs: settings.commandTimeoutMs,
    ),
  );
  return SandboxLayers(fs: fs, shell: shell);
}

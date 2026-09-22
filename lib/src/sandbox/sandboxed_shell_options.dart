/// 沙箱执行器的构造选项。
library;

import 'command_policy.dart';
import 'sandbox_probe.dart';

/// [SandboxedShellExecutor] 的构造选项。
class SandboxedShellOptions {
  const SandboxedShellOptions({
    required this.backend,
    required this.root,
    required this.commandPolicy,
    this.minimalEnv,
    this.maxOutputBytes = 1 << 20,
    this.maxTimeoutMs = 600000,
    this.networkAllowlist = const <String>{},
  });

  /// 已探测到的 launcher 后端。
  final SandboxBackend backend;

  /// 规范化后的沙箱根。
  final String root;

  /// 命令策略（执行前裁决）。
  final CommandPolicy commandPolicy;

  /// 传给 launcher 的最小环境；缺省从父进程拷贝常用键。
  final Map<String, String>? minimalEnv;

  /// 单路输出采集上限（字节）。
  final int maxOutputBytes;

  /// 单次超时上限（毫秒）。
  final int maxTimeoutMs;

  /// 放行网络的命令前缀白名单；命中则不传 `--no-net`。
  final Set<String> networkAllowlist;
}

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
    this.allowNetwork = false,
    this.writablePaths = const <String>{},
    this.minimalEnv,
    this.maxOutputBytes = 1 << 20,
    this.maxTimeoutMs = 600000,
    this.networkAllowlist = const <String>{},
  });

  /// 已探测到的 sandbox-exec 后端。
  final SandboxBackend backend;

  /// 规范化后的沙箱根。
  final String root;

  /// 命令策略（执行前裁决）。
  final CommandPolicy commandPolicy;

  /// 放行全部命令的网络（[networkAllowlist] 之外的全局开关）；缺省关闭。
  final bool allowNetwork;

  /// 额外可写路径（已展开 `~`、相对路径基于 root 解析）；与
  /// `defaultWritableCaches` 合并后进 Seatbelt 可写根。
  final Set<String> writablePaths;

  /// 传给 sandbox-exec 的最小环境；缺省从父进程拷贝常用键。
  final Map<String, String>? minimalEnv;

  /// 单路输出采集上限（字节）。
  final int maxOutputBytes;

  /// 单次超时上限（毫秒）。
  final int maxTimeoutMs;

  /// 放行网络的命令前缀白名单；命中则不附加 `(deny network*)`。
  final Set<String> networkAllowlist;
}

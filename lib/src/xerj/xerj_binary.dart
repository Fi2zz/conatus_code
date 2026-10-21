/// XERJ 可执行文件的发现。
///
/// XERJ 是外部 Rust 单二进制，不随包分发：只承认 PATH 上的 `xerj`，
/// 找不到时调用方静默跳过全部工具（与 ripgrep 的降级方式一致）。
library;

import 'dart:io';

/// 已发现的 XERJ 可执行文件。
class XerjBinary {
  const XerjBinary(this.path);

  /// 可执行文件路径（当前只支持 PATH 上的 `xerj`）。
  final String path;

  /// 探测系统 `xerj`；[probe] 是测试注入点。
  static XerjBinary? discover({bool Function()? probe}) {
    if (!(probe ?? _probeSystem)()) return null;
    return const XerjBinary('xerj');
  }

  static bool _probeSystem() {
    try {
      return Process.runSync('xerj', <String>['--version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}

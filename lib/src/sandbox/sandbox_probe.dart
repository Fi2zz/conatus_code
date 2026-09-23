/// 沙箱后端（/usr/bin/sandbox-exec）的启动预检：fail-closed，不可用即抛。
library;

import 'dart:io';

/// 沙箱后端（sandbox-exec）的位置信息。
class SandboxBackend {
  const SandboxBackend({required this.sandboxExecPath});

  /// 系统 sandbox-exec 的绝对路径（macOS 自带）。
  final String sandboxExecPath;
}

/// 沙箱不可用时的异常。
class SandboxException implements Exception {
  const SandboxException(this.message);

  final String message;

  @override
  String toString() => 'SandboxException: $message';
}

/// 探测沙箱后端是否可用；不可用抛 [SandboxException]（fail-closed，不降级）。
///
/// [env] 保留以兼容既有调用点（sandbox-exec 直执后不再需要外部定位信息）；
/// [checkRosetta] 已废弃（原生二进制，无 Rosetta 依赖），传入值被忽略。
SandboxBackend probeSandboxBackend({
  Map<String, String>? env,
  bool checkRosetta = true,
}) {
  if (!Platform.isMacOS) {
    throw const SandboxException('本阶段仅支持 macOS');
  }
  const String execPath = '/usr/bin/sandbox-exec';
  _requireSandboxExec(execPath);
  _probeLaunch(execPath);
  return const SandboxBackend(sandboxExecPath: execPath);
}

/// 校验系统自带 sandbox-exec；缺失说明 Seatbelt 不可用。
void _requireSandboxExec(String execPath) {
  final File file = File(execPath);
  final bool usable = file.existsSync();
  if (!usable) {
    throw SandboxException('未找到 $execPath，沙箱不可用');
  }
}

/// 试跑最小 profile：非零退出或缺输出说明 Seatbelt 不可用（fail-closed）。
void _probeLaunch(String execPath) {
  final ProcessResult result = Process.runSync(
    execPath,
    <String>['-p', '(version 1)(allow default)', '/bin/sh', '-c', 'echo sb-ok'],
  );
  final bool ok =
      result.exitCode == 0 && result.stdout.toString().contains('sb-ok');
  if (!ok) {
    throw SandboxException('sandbox-exec 试跑失败（exit ${result.exitCode}），'
        'Seatbelt 不可用');
  }
}

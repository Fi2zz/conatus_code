/// 沙箱后端（/usr/bin/sandbox-exec）的启动预检：fail-closed，不可用即抛。
library;

import 'dart:io';

/// 沙箱后端类型。
enum SandboxBackendKind {
  /// macOS Seatbelt（sandbox-exec）。
  seatbelt,

  /// Linux bubblewrap。
  bubblewrap,
}

/// 沙箱后端的位置信息。
class SandboxBackend {
  const SandboxBackend({
    required this.sandboxExecPath,
    this.kind = SandboxBackendKind.seatbelt,
  });

  /// 后端可执行文件的绝对路径（sandbox-exec 或 bwrap）。
  final String sandboxExecPath;

  /// 后端类型。
  final SandboxBackendKind kind;
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
  if (Platform.isMacOS) {
    const String execPath = '/usr/bin/sandbox-exec';
    _requireSandboxExec(execPath);
    _probeLaunch(execPath);
    return const SandboxBackend(sandboxExecPath: execPath);
  }
  if (Platform.isLinux) return _probeBubblewrap();
  throw const SandboxException('OS 沙箱仅支持 macOS（Seatbelt）与 Linux（bubblewrap）');
}

/// 探测 Linux bubblewrap：先找二进制，再试跑最小只读沙箱。
SandboxBackend _probeBubblewrap() {
  final String? path = _findBubblewrap();
  if (path == null) {
    throw const SandboxException('未找到 bwrap（bubblewrap），沙箱不可用');
  }
  final ProcessResult result = Process.runSync(
    path,
    <String>['--ro-bind', '/', '/', '--', '/bin/sh', '-c', 'echo sb-ok'],
  );
  final bool ok =
      result.exitCode == 0 && result.stdout.toString().contains('sb-ok');
  if (!ok) {
    throw SandboxException(
      'bwrap 试跑失败（exit ${result.exitCode}），bubblewrap 不可用',
    );
  }
  return SandboxBackend(
    sandboxExecPath: path,
    kind: SandboxBackendKind.bubblewrap,
  );
}

String? _findBubblewrap() {
  for (final String path in <String>[
    '/usr/bin/bwrap',
    '/bin/bwrap',
    '/usr/local/bin/bwrap',
  ]) {
    if (File(path).existsSync()) return path;
  }
  try {
    final ProcessResult result = Process.runSync('which', <String>['bwrap']);
    final String found = result.stdout.toString().trim();
    if (result.exitCode == 0 && found.isNotEmpty) return found;
  } on ProcessException {
    // 没有 which 时只能依赖常见路径。
  }
  return null;
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

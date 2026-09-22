/// 沙箱后端（launcher 二进制）的启动预检：fail-closed，不可用即抛。
library;

import 'dart:io';

/// 沙箱后端（launcher）的位置信息。
class SandboxBackend {
  const SandboxBackend({required this.launcherPath});

  /// 规范化后的 launcher 绝对路径（已确保可执行）。
  final String launcherPath;
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
/// [checkRosetta] 为 false 时跳过 `--help` 试跑（本机已确认可执行时用于提速）。
SandboxBackend probeSandboxBackend({
  Map<String, String>? env,
  bool checkRosetta = true,
}) {
  if (!Platform.isMacOS) {
    throw const SandboxException('本阶段仅支持 macOS');
  }
  _requireSandboxExec();
  final String launcher = _findLauncher(env);
  final String realPath = _normalizeAndChmod(launcher);
  if (checkRosetta) {
    _probeLaunch(realPath);
  }
  return SandboxBackend(launcherPath: realPath);
}

/// 校验系统自带 sandbox-exec；缺失说明 Seatbelt 不可用。
void _requireSandboxExec() {
  if (!File('/usr/bin/sandbox-exec').existsSync()) {
    throw const SandboxException('未找到 /usr/bin/sandbox-exec，沙箱不可用');
  }
}

/// 在 pub 缓存中定位 launcher：`hosted/<镜像>/workspace_sandbox-*/bin/macos/x64/`。
String _findLauncher(Map<String, String>? env) {
  final String hosted = '${_pubCacheRoot(env)}/hosted';
  final Directory hostedDir = Directory(hosted);
  if (!hostedDir.existsSync()) {
    throw SandboxException('未找到 workspace_sandbox 的 launcher 二进制（pub 缓存：$hosted）');
  }
  for (final FileSystemEntity mirror in hostedDir.listSync()) {
    if (mirror is! Directory) continue;
    for (final FileSystemEntity pkg in mirror.listSync()) {
      if (pkg is! Directory || !pkg.path.contains('workspace_sandbox-')) continue;
      final String candidate = '${pkg.path}/bin/macos/x64/workspace_launcher';
      if (File(candidate).existsSync()) return candidate;
    }
  }
  throw SandboxException('未找到 workspace_sandbox 的 launcher 二进制（pub 缓存：$hosted）');
}

/// PUB_CACHE 优先，其次 `$HOME/.pub-cache`。
String _pubCacheRoot(Map<String, String>? env) {
  final String? configured = env?['PUB_CACHE'];
  if (configured != null && configured.isNotEmpty) return configured;
  final String? fromPlatform = Platform.environment['PUB_CACHE'];
  if (fromPlatform != null && fromPlatform.isNotEmpty) return fromPlatform;
  final String? home = Platform.environment['HOME'];
  if (home == null) {
    throw const SandboxException('未设置 HOME，无法定位 pub 缓存');
  }
  return '$home/.pub-cache';
}

/// 规范化路径（去符号链接）并确保可执行位；chmod 失败不致命。
String _normalizeAndChmod(String path) {
  final String real = File(path).resolveSymbolicLinksSync();
  try {
    Process.runSync('chmod', <String>['+x', real]);
  } on ProcessException {
    // launcher 可能本身已可执行。
  }
  return real;
}

/// 试跑 `--help`：非零退出说明二进制不可执行（含 Rosetta 2 缺失）。
void _probeLaunch(String launcherPath) {
  final ProcessResult result = Process.runSync(launcherPath, <String>['--help']);
  if (result.exitCode != 0) {
    throw SandboxException(
        'launcher 试跑失败（exit ${result.exitCode}），可能缺少 Rosetta 2');
  }
}

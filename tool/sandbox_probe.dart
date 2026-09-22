// workspace_sandbox 在本机（arm64 macOS / Rosetta）的可用性探测。
//
// 覆盖两件事：launcher 能否被定位（probeSandboxBackend 会 chmod +x 并试跑
// --help）、Seatbelt 沙箱后端是否就绪。失败时打印错误并以非零退出。
// 正式版的启动预检在 lib/src/sandbox/sandbox_probe.dart。
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';

Future<void> main() async {
  stdout.writeln('cwd: ${Directory.current.path}');
  try {
    final SandboxBackend backend = probeSandboxBackend();
    stdout.writeln('launcherPath: ${backend.launcherPath}');
    final ProcessResult probe = Process.runSync(backend.launcherPath, ['--help']);
    stdout.writeln('launcher --help exit: ${probe.exitCode}');
    stdout.writeln('后端可用');
  } on SandboxException catch (error) {
    stderr.writeln('沙箱后端不可用：${error.message}');
    exit(1);
  }
}

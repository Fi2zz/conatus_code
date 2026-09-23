// sandbox-exec 后端在本机（macOS）的可用性探测。
//
// 覆盖：/usr/bin/sandbox-exec 存在且 smoke 试跑通过（probeSandboxBackend 内部
// 以最小 profile 跑 `echo sb-ok`）。失败时打印错误并以非零退出。
// 正式版的启动预检在 lib/src/sandbox/sandbox_probe.dart。
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';

Future<void> main() async {
  stdout.writeln('cwd: ${Directory.current.path}');
  try {
    final SandboxBackend backend = probeSandboxBackend();
    stdout.writeln('sandboxExecPath: ${backend.sandboxExecPath}');
    stdout.writeln('后端可用');
  } on SandboxException catch (error) {
    stderr.writeln('沙箱后端不可用：${error.message}');
    exit(1);
  }
}

/// 沙箱执行的集成测试：真实 sandbox-exec + Seatbelt（macOS 本机）。
///
/// 后端不可用时整体跳过（markTestSkipped），保证 CI 无沙箱环境不红。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 集成用可执行白名单（含回归用例需要的 git/mkdir）。
const Set<String> _integrationExecutables = <String>{
  'sh', 'bash', 'curl', 'echo', 'touch', 'rm', 'ls', 'cat', 'pwd', 'git',
  'mkdir',
};

CommandPolicy _integrationPolicy(String root) => CommandPolicy(
      root: root,
      allowedExecutables: _integrationExecutables,
    );

void main() {
  SandboxBackend? backend;
  String? root;
  SandboxedShellExecutor? defaultShell;
  SandboxedShellExecutor? integrationShell;
  SandboxedShellExecutor? writableShell;

  setUpAll(() {
    try {
      final SandboxBackend found = probeSandboxBackend();
      backend = found;
      final Directory tmp = Directory.systemTemp.createTempSync('cc-sb-');
      root = tmp.resolveSymbolicLinksSync();
      defaultShell = SandboxedShellExecutor(
        options: SandboxedShellOptions(
          backend: found,
          root: root!,
          commandPolicy: CommandPolicy(root: root!),
        ),
      );
      integrationShell = SandboxedShellExecutor(
        options: SandboxedShellOptions(
          backend: found,
          root: root!,
          commandPolicy: _integrationPolicy(root!),
        ),
      );
      writableShell = SandboxedShellExecutor(
        options: SandboxedShellOptions(
          backend: found,
          root: root!,
          commandPolicy: CommandPolicy(
            root: root!,
            allowedExecutables: _integrationExecutables,
            readAllowedPaths:
                resolveReadAllowedPaths(<String>['~/cc-sb-writable']),
          ),
          writablePaths: <String>{'~/cc-sb-writable'},
        ),
      );
    } on SandboxException {
      // 后端不可用：各用例跳过。
    }
  });

  /// 取集成 shell；后端不可用时跳过当前测试（markTestSkipped 在当前 test 版本
  /// 下只标记不终止，必须显式终止，否则后面的空断言会以错误形式报出）。
  SandboxedShellExecutor requireShell(SandboxedShellExecutor? executor) {
    if (executor == null) {
      markTestSkipped('沙箱后端不可用，跳过集成测试');
      throw StateError('unreachable：markTestSkipped 未终止执行');
    }
    return executor;
  }

  String home() => Platform.environment['HOME'] ?? '';

  test('probeSandboxBackend 定位 sandbox-exec', () {
    final SandboxBackend? found = backend;
    if (found == null) {
      markTestSkipped('沙箱后端不可用，跳过集成测试');
      return;
    }
    expect(found.sandboxExecPath, endsWith('sandbox-exec'));
  });

  test('echo hello：exit 0', () async {
    final SandboxedShellExecutor shell = requireShell(integrationShell);
    final ShellRunResult result =
        await shell.run(shell.resolve(const ShellExecRequest(command: 'echo hello')));

    expect(result.exitCode, 0);
    expect(result.stdout.text, contains('hello'));
  });

  test('重定向 /dev/null：exit 0（flutter shim 的 git 探测回归）', () async {
    final SandboxedShellExecutor shell = requireShell(integrationShell);
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'echo hi >/dev/null 2>&1')));

    expect(result.exitCode, 0);
  });

  test('git --version >/dev/null 2>&1：exit 0', () async {
    final SandboxedShellExecutor shell = requireShell(integrationShell);
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'git --version >/dev/null 2>&1')));

    expect(result.exitCode, 0);
  });

  test('写 pub 缓存（touch ~/.pub-cache/cc-sb-probe）→ exit 0 且落盘', () async {
    final SandboxedShellExecutor shell = requireShell(integrationShell);
    final File probe = File('${home()}/.pub-cache/cc-sb-probe');
    addTearDown(() {
      if (probe.existsSync()) probe.deleteSync();
    });
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'touch ~/.pub-cache/cc-sb-probe')));

    expect(result.exitCode, 0);
    expect(probe.existsSync(), isTrue);
  });

  test('writable_paths 自定义目录可写', () async {
    final SandboxedShellExecutor shell = requireShell(writableShell);
    final Directory dir = Directory('${home()}/cc-sb-writable');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'mkdir -p ~/cc-sb-writable')));
    expect(result.exitCode, 0);

    result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'touch ~/cc-sb-writable/probe.txt')));

    expect(result.exitCode, 0);
    expect(File('${dir.path}/probe.txt').existsSync(), isTrue);
  });

  test('断网：curl 网络白名单外 → 非零退出', () async {
    final SandboxedShellExecutor shell = requireShell(integrationShell);
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'curl -s --max-time 5 https://example.com')));

    expect(result.exitCode, isNot(0));
  });

  test('命令策略拒绝（rm -rf /）→ exitCode null 且 stderr 含拒绝', () async {
    final SandboxedShellExecutor shell = requireShell(defaultShell);
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'rm -rf /')));

    expect(result.exitCode, isNull);
    expect(result.stderr.text, contains('拒绝'));
  });

  test('越界写（touch ~/cc-sb-out.txt）→ 非零（Seatbelt 拦截）', () async {
    final SandboxedShellExecutor shell = requireShell(integrationShell);
    final File probe = File('${home()}/cc-sb-out.txt');
    addTearDown(() {
      if (probe.existsSync()) probe.deleteSync();
    });
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'touch ~/cc-sb-out.txt')));

    expect(result.exitCode, isNot(0));
    expect(probe.existsSync(), isFalse);
  });

  test('沙箱内写（touch in.txt）→ exit 0', () async {
    final SandboxedShellExecutor shell = requireShell(integrationShell);
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'touch in.txt')));

    expect(result.exitCode, 0);
    expect(File('$root/in.txt').existsSync(), isTrue);
  });

  test('cwd 越界 → 拒绝（exitCode null 且 stderr 含越界）', () async {
    final SandboxedShellExecutor shell = requireShell(defaultShell);
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'echo hi', workdir: '/etc')));

    expect(result.exitCode, isNull);
    expect(result.stderr.text, contains('越界'));
  });
}

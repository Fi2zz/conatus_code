/// 沙箱执行的集成测试：真实 launcher + Seatbelt（macOS 本机）。
///
/// 后端不可用时整体跳过（markTestSkipped），保证 CI 无 launcher 环境不红。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 集成策略：默认白名单外加 curl（断网用例需要它真正执行到 Seatbelt 层）。
CommandPolicy _integrationPolicy(String root) => CommandPolicy(
      root: root,
      allowedExecutables: <String>{
        'sh', 'bash', 'curl', 'echo', 'touch', 'rm', 'ls', 'cat', 'pwd',
      },
    );

void main() {
  SandboxBackend? backend;
  String? root;
  SandboxedShellExecutor? defaultShell;
  SandboxedShellExecutor? integrationShell;

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
    } on SandboxException {
      // 后端不可用：各用例跳过。
    }
  });

  /// 取集成 shell；后端不可用时跳过当前测试（markTestSkipped 抛异常）。
  SandboxedShellExecutor requireIntegrationShell() {
    final SandboxedShellExecutor? executor = integrationShell;
    if (executor == null) {
      markTestSkipped('沙箱后端不可用，跳过集成测试');
      return executor!;
    }
    return executor;
  }

  /// 取默认策略 shell（命令拒绝用例需要默认白名单）。
  SandboxedShellExecutor requireDefaultShell() {
    final SandboxedShellExecutor? executor = defaultShell;
    if (executor == null) {
      markTestSkipped('沙箱后端不可用，跳过集成测试');
      return executor!;
    }
    return executor;
  }

  test('probeSandboxBackend 定位 launcher', () {
    final SandboxBackend? found = backend;
    if (found == null) {
      markTestSkipped('沙箱后端不可用，跳过集成测试');
      return;
    }
    expect(found.launcherPath, endsWith('workspace_launcher'));
  });

  test('echo hello：exit 0 且 stderr 剥离 [Launcher] 日志', () async {
    final SandboxedShellExecutor shell = requireIntegrationShell();
    final ShellRunResult result =
        await shell.run(shell.resolve(const ShellExecRequest(command: 'echo hello')));

    expect(result.exitCode, 0);
    expect(result.stdout.text, contains('hello'));
    expect(result.stderr.text, isNot(contains('[Launcher]')));
  });

  test('断网：curl 网络白名单外 → 非零退出', () async {
    final SandboxedShellExecutor shell = requireIntegrationShell();
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'curl -s --max-time 5 https://example.com')));

    expect(result.exitCode, isNot(0));
  });

  test('命令策略拒绝（rm -rf /）→ exitCode null 且 stderr 含拒绝', () async {
    final SandboxedShellExecutor shell = requireDefaultShell();
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'rm -rf /')));

    expect(result.exitCode, isNull);
    expect(result.stderr.text, contains('拒绝'));
  });

  test('越界写（touch /tmp/cc-sb-out.txt）→ 非零（Seatbelt 拦截）', () async {
    final SandboxedShellExecutor shell = requireIntegrationShell();
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'touch /tmp/cc-sb-out.txt')));

    expect(result.exitCode, isNot(0));
  });

  test('沙箱内写（touch in.txt）→ exit 0', () async {
    final SandboxedShellExecutor shell = requireIntegrationShell();
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'touch in.txt')));

    expect(result.exitCode, 0);
    expect(File('$root/in.txt').existsSync(), isTrue);
  });

  test('cwd 越界 → 拒绝（exitCode null 且 stderr 含越界）', () async {
    final SandboxedShellExecutor shell = requireDefaultShell();
    final ShellRunResult result = await shell.run(shell.resolve(
        const ShellExecRequest(command: 'echo hi', workdir: '/etc')));

    expect(result.exitCode, isNull);
    expect(result.stderr.text, contains('越界'));
  });
}

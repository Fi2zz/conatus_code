/// 沙箱 REVIEW → 人工复核接线：prompter 允许/拒绝/缺失/抛错四种行为。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 假 sandbox-exec：剥掉 `-p <profile> <params> --` 前缀后原样 exec，
/// 让命令在无 Seatbelt 的测试环境真实跑起来。
SandboxBackend _fakeBackend(Directory dir) {
  final File script = File('${dir.path}/sandbox-exec');
  script.writeAsStringSync(
    '#!/bin/sh\nwhile [ "\$1" != "--" ]; do shift; done\nshift\nexec "\$@"\n',
  );
  Process.runSync('chmod', <String>['755', script.path]);
  return SandboxBackend(sandboxExecPath: script.path);
}

SandboxedShellExecutor _executor(Directory dir) => SandboxedShellExecutor(
  options: SandboxedShellOptions(
    backend: _fakeBackend(dir),
    root: dir.path,
    // sleep 不在缺省白名单：复合命令要走到 review（而非被白名单 deny 截胡）。
    commandPolicy: CommandPolicy(
      root: dir.path,
      allowedExecutables: resolveAllowedExecutables(const <String>['sleep']),
    ),
  ),
);

ShellExecSpec _spec(SandboxedShellExecutor executor, String command) =>
    executor.resolve(ShellExecRequest(command: command));

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sandbox-review');
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  test('review 未接线 prompter → 拒绝（维持 fail-closed 现状）', () async {
    final SandboxedShellExecutor executor = _executor(dir);
    final ShellRunResult result = await executor.run(
      _spec(executor, 'echo a && echo b'),
    );
    expect(result.exitCode, isNull);
    expect(result.stderr.text, contains('命令被拒绝'));
  });

  test('review + 人工允许 → 照常执行（出码 0、有 stdout）', () async {
    final SandboxedShellExecutor executor = _executor(dir);
    String? askedCommand;
    String? askedReason;
    executor.reviewPrompter = (String command, String reason) async {
      askedCommand = command;
      askedReason = reason;
      return true;
    };

    final ShellRunResult result = await executor.run(
      _spec(executor, 'echo ok && echo done'),
    );

    expect(askedCommand, 'echo ok && echo done');
    expect(askedReason, isNotEmpty);
    expect(result.exitCode, 0);
    expect(result.stdout.text, contains('ok'));
    expect(result.stdout.text, contains('done'));
  });

  test('review + 人工拒绝 → 拒绝且说明未获复核通过', () async {
    final SandboxedShellExecutor executor = _executor(dir);
    executor.reviewPrompter = (String command, String reason) async => false;

    final ShellRunResult result = await executor.run(
      _spec(executor, 'echo a && echo b'),
    );

    expect(result.exitCode, isNull);
    expect(result.stderr.text, contains('未获人工复核通过'));
  });

  test('review + prompter 抛错 → fail-closed 拒绝', () async {
    final SandboxedShellExecutor executor = _executor(dir);
    executor.reviewPrompter = (String command, String reason) async =>
        throw StateError('审批浮层故障');

    final ShellRunResult result = await executor.run(
      _spec(executor, 'echo a && echo b'),
    );

    expect(result.exitCode, isNull);
    expect(result.stderr.text, contains('未获人工复核通过'));
  });

  test('start()：review + 拒绝 → 假进程句柄带拒绝理由', () async {
    final SandboxedShellExecutor executor = _executor(dir);
    executor.reviewPrompter = (String command, String reason) async => false;

    final ShellProcess process = await executor.start(
      _spec(executor, 'echo a && echo b'),
    );

    expect(process.status, ShellProcessStatus.completed);
    expect(process.exitCode, isNull);
    expect(process.readOutput().delta, contains('未获人工复核通过'));
  });

  test('start()：review + 允许 → 真进程跑起来，可读输出可 kill', () async {
    final SandboxedShellExecutor executor = _executor(dir);
    executor.reviewPrompter = (String command, String reason) async => true;

    final ShellProcess process = await executor.start(
      _spec(executor, 'echo bg-ok && sleep 30'),
    );
    addTearDown(process.kill);

    expect(process.status, ShellProcessStatus.running);
    String delta = '';
    for (int i = 0; i < 50 && delta.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      delta = process.readOutput().delta;
    }
    expect(delta, contains('bg-ok'));
    expect(process.kill(), isTrue);
  });
}

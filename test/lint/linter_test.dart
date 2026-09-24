/// LinterService：探测映射、编辑后追加告警、去抖、enabled/覆盖。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import '../fs_tools/support/fake_shell.dart';

ShellRunResult _lint({String stderr = ''}) => ShellRunResult(
      exitCode: 1,
      timedOut: false,
      timeoutMs: 30000,
      stdout: const CollectedOutput(text: ''),
      stderr: CollectedOutput(text: stderr),
    );

/// 建一个带假 shell + write_file 工具的上下文并挂 linter 中间件。
Future<(Context, FakeShellExecutor)> _boot({
  required LintConfig config,
  required String workdir,
  ShellRunResult lintResult = const ShellRunResult(
    exitCode: 1,
    timedOut: false,
    timeoutMs: 0,
    stdout: CollectedOutput(text: ''),
    stderr: CollectedOutput(text: ''),
  ),
}) async {
  final Context app = Context.root();
  provideTools(app);
  final FakeShellExecutor shell = FakeShellExecutor(lintResult);
  provideLinter(app, config: config, workdir: workdir, shell: shell);
  app.effect(() => app.tools.fn(
        'write_file',
        description: '写文件',
        params: <ParamSpec>[ParamSpec.string('path', required: true)],
        handler: (ToolContext ctx) async => ToolResult.success('已写入'),
      ));
  return (app, shell);
}

void main() {
  test('按项目类型探测：pubspec.yaml → dart analyze', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-lint');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsStringSync('name: x\n');

    final Context app = Context.root();
    provideTools(app);
    final FakeShellExecutor shell = FakeShellExecutor(_lint(stderr: '告警A'));
    final LinterService linter = provideLinter(
      app,
      config: const LintConfig(),
      workdir: dir.path,
      shell: shell,
    );
    addTearDown(app.dispose);

    final String? warnings = await linter.runIfDue();
    expect(warnings, contains('告警A'));
    expect(shell.lastRequest!.command, 'dart analyze');
    expect(shell.lastRequest!.workdir, dir.path);
  });

  test('编辑工具成功返回后追加 [Lint] 告警', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-lint');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsStringSync('name: x\n');
    final (Context app, FakeShellExecutor shell) = await _boot(
      config: const LintConfig(),
      workdir: dir.path,
      lintResult: _lint(stderr: '未使用的变量 x'),
    );
    addTearDown(app.dispose);

    final ToolResult result = await app.tools.call(const ToolCall(
      name: 'write_file',
      arguments: <String, Object?>{'path': 'a.dart'},
    ));

    expect(result.isError, isFalse);
    expect(result.content, contains('已写入'));
    expect(result.content, contains('[Lint]'));
    expect(result.content, contains('未使用的变量 x'));
  });

  test('去抖：窗口内第二次编辑不触发 lint', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-lint');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsStringSync('name: x\n');
    final (Context app, FakeShellExecutor shell) = await _boot(
      config: const LintConfig(),
      workdir: dir.path,
      lintResult: _lint(stderr: '告警'),
    );
    addTearDown(app.dispose);

    await app.tools.call(const ToolCall(
      name: 'write_file',
      arguments: <String, Object?>{'path': 'a.dart'},
    ));
    final int runsAfterFirst = shell.calls;
    final ToolResult second = await app.tools.call(const ToolCall(
      name: 'write_file',
      arguments: <String, Object?>{'path': 'b.dart'},
    ));

    expect(runsAfterFirst, greaterThan(0));
    expect(shell.calls, runsAfterFirst); // 第二次未跑 lint
    expect(second.content, isNot(contains('[Lint]')));
  });

  test('enabled=false 不触发；command 覆盖探测', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-lint');
    addTearDown(() => dir.deleteSync(recursive: true));
    // 无 pubspec → 探测应无 linter；但配置覆盖为 eslint。
    final Context app = Context.root();
    provideTools(app);
    final FakeShellExecutor shell = FakeShellExecutor(_lint(stderr: 'eslint!'));
    final LinterService linter = provideLinter(
      app,
      config: const LintConfig(command: 'eslint .'),
      workdir: dir.path,
      shell: shell,
    );
    addTearDown(app.dispose);
    expect(await linter.runIfDue(), contains('eslint!'));
    expect(shell.lastRequest!.command, 'eslint .');

    final LinterService disabled = LinterService(
      shell: shell,
      config: const LintConfig(enabled: false),
      workdir: dir.path,
    );
    expect(await disabled.runIfDue(), isNull);
  });

  test('非编辑工具不触发 lint', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-lint');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsStringSync('name: x\n');
    final (Context app, FakeShellExecutor shell) = await _boot(
      config: const LintConfig(),
      workdir: dir.path,
      lintResult: _lint(stderr: '告警'),
    );
    addTearDown(app.dispose);

    final ToolResult result = await app.tools.call(const ToolCall(
      name: 'get_time',
    ));
    expect(result.content, isNot(contains('[Lint]')));
  });
}

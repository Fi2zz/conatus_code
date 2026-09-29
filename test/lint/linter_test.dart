/// LinterService：探针探测、编辑后追加告警、按目标集合去抖、enabled/覆盖。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import '../fs_tools/support/fake_shell.dart';

/// 原始文本形态的校验输出（走 stderr，exitCode != 0）。
ShellRunResult _textLint(String stderr) => ShellRunResult(
      exitCode: 1,
      timedOut: false,
      timeoutMs: 30000,
      stdout: const CollectedOutput(text: ''),
      stderr: CollectedOutput(text: stderr),
    );

/// machine 形态的校验输出：每行 `SEVERITY|TYPE|CODE|path|line|col|len|消息`。
ShellRunResult _machineLint(List<String> lines) => ShellRunResult(
      exitCode: 3,
      timedOut: false,
      timeoutMs: 30000,
      stdout: CollectedOutput(text: lines.join('\n')),
      stderr: const CollectedOutput(text: ''),
    );

/// 一条 machine 诊断行。
String _diag(String severity, String code, String path, int line, int col,
        String message) =>
    '$severity|TYPE|$code|$path|$line|$col|2|$message';

/// 建一个带假 shell + write_file 工具的上下文并挂 linter 中间件。
Future<(Context, FakeShellExecutor)> _boot({
  required LintConfig config,
  required String workdir,
  ShellRunResult? lintResult,
}) async {
  final Context app = Context.root();
  provideTools(app);
  final FakeShellExecutor shell =
      FakeShellExecutor(lintResult ?? _textLint('告警'));
  provideLinter(app, config: config, workdir: workdir, shell: shell);
  app.effect(() => app.tools.fn(
        'write_file',
        description: '写文件',
        params: <ParamSpec>[ParamSpec.string('path', required: true)],
        handler: (ToolContext ctx) async => ToolResult.success('已写入'),
      ));
  return (app, shell);
}

/// 建一个 Dart 形状的临时项目（pubspec.yaml + lib/a.dart、lib/b.dart）。
Directory _dartProject(String tag) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-lint-$tag');
  final String root = dir.path;
  final String sep = Platform.pathSeparator;
  File('$root${sep}pubspec.yaml').writeAsStringSync('name: x\n');
  for (final String name in <String>['a', 'b']) {
    File('$root${sep}lib$sep$name.dart').createSync(recursive: true);
  }
  return dir;
}

void main() {
  test('Dart 项目：限定到改动文件 + 机器格式命令', () async {
    final Directory dir = _dartProject('probe');
    addTearDown(() => dir.deleteSync(recursive: true));
    final Context app = Context.root();
    provideTools(app);
    final FakeShellExecutor shell = FakeShellExecutor(_machineLint(<String>[]));
    final LinterService linter = provideLinter(
      app,
      config: const LintConfig(),
      workdir: dir.path,
      shell: shell,
    );
    addTearDown(app.dispose);

    expect(await linter.runIfDue(<String>['lib/a.dart']), isNull);
    // 探针是首次调用时才探测的，所以先跑一次再断言命令形状。
    expect(linter.command, 'dart analyze --format=machine {file}');
    expect(shell.lastRequest!.command,
        "dart analyze --format=machine 'lib/a.dart'");
  });

  test('machine 输出回灌为结构化告警（错误带码与行列）', () async {
    final Directory dir = _dartProject('machine');
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, FakeShellExecutor shell) = await _boot(
      config: const LintConfig(),
      workdir: dir.path,
      lintResult: _machineLint(<String>[
        _diag('WARNING', 'UNUSED_ELEMENT',
            '${dir.path}${Platform.pathSeparator}lib/a.dart', 3, 8, '没被引用'),
        _diag('ERROR', 'RETURN_OF_INVALID_TYPE',
            '${dir.path}${Platform.pathSeparator}lib/a.dart', 1, 15,
            '返回值类型不对'),
      ]),
    );
    addTearDown(app.dispose);

    final ToolResult result = await app.tools.call(const ToolCall(
      name: 'write_file',
      arguments: <String, Object?>{'path': 'lib/a.dart'},
    ));

    expect(result.content, contains('[Lint]'));
    // 路径压成相对短路径，错误排在警告之前。
    expect(result.content, contains('lib/a.dart'));
    expect(result.content, contains('ERROR [1:15] RETURN_OF_INVALID_TYPE'));
    expect(
      result.content.indexOf('ERROR'),
      lessThan(result.content.indexOf('WARNING')),
    );
  });

  test('无法解析的输出不产生 [Lint]（不把用法提示当告警）', () async {
    final Directory dir = _dartProject('garbage');
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, FakeShellExecutor shell) = await _boot(
      config: const LintConfig(),
      workdir: dir.path,
      lintResult: _machineLint(<String>[
        'Directory or file doesn\'t exist: lib/a.dart',
        '',
        'Usage: dart analyze [arguments] [<directory>]',
      ]),
    );
    addTearDown(app.dispose);

    final ToolResult result = await app.tools.call(const ToolCall(
      name: 'write_file',
      arguments: <String, Object?>{'path': 'lib/a.dart'},
    ));
    expect(shell.lastRequest, isNotNull); // 确实跑过
    expect(result.content, isNot(contains('[Lint]')));
  });

  test('改动文件已不存在时不跑校验（apply_patch 会删文件）', () async {
    final Directory dir = _dartProject('gone');
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, FakeShellExecutor shell) = await _boot(
      config: const LintConfig(),
      workdir: dir.path,
      lintResult: _machineLint(<String>[]),
    );
    addTearDown(app.dispose);

    await app.tools.call(const ToolCall(
      name: 'write_file',
      arguments: <String, Object?>{'path': 'lib/deleted.dart'},
    ));
    expect(shell.calls, 0);
  });

  test('去抖按目标集合分键：同文件抑制、异文件不抑制', () async {
    final Directory dir = _dartProject('debounce');
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, FakeShellExecutor shell) = await _boot(
      config: const LintConfig(),
      workdir: dir.path,
      lintResult: _machineLint(<String>[]),
    );
    addTearDown(app.dispose);

    Future<void> edit(String path) => app.tools.call(ToolCall(
          name: 'write_file',
          arguments: <String, Object?>{'path': path},
        ));

    await edit('lib/a.dart');
    final int afterFirst = shell.calls;
    expect(afterFirst, 1);

    await edit('lib/a.dart'); // 同一目标 → 窗口内被抑制
    expect(shell.calls, afterFirst);

    await edit('lib/b.dart'); // 不同目标 → 各自该查一次
    expect(shell.calls, afterFirst + 1);
  });

  test('command 覆盖走原始文本；enabled=false 不触发', () async {
    final Directory dir = _dartProject('override');
    addTearDown(() => dir.deleteSync(recursive: true));
    final Context app = Context.root();
    provideTools(app);
    final FakeShellExecutor shell = FakeShellExecutor(_textLint('eslint!'));
    // 无 {file} 占位符 → 不限定文件，也不依赖改动路径。
    final LinterService linter = provideLinter(
      app,
      config: const LintConfig(command: 'eslint .'),
      workdir: dir.path,
      shell: shell,
    );
    addTearDown(app.dispose);

    expect(await linter.runIfDue(<String>[]), contains('eslint!'));
    expect(shell.lastRequest!.command, 'eslint .');

    final LinterService disabled = LinterService(
      shell: shell,
      config: const LintConfig(enabled: false),
      workdir: dir.path,
    );
    expect(await disabled.runIfDue(<String>[]), isNull);
  });

  test('非编辑工具不触发 lint', () async {
    final Directory dir = _dartProject('noop');
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, FakeShellExecutor shell) = await _boot(
      config: const LintConfig(),
      workdir: dir.path,
      lintResult: _machineLint(<String>[
        _diag('ERROR', 'X', 'lib/a.dart', 1, 1, 'x'),
      ]),
    );
    addTearDown(app.dispose);

    final ToolResult result =
        await app.tools.call(const ToolCall(name: 'get_time'));
    expect(result.content, isNot(contains('[Lint]')));
    expect(shell.calls, 0);
  });
}

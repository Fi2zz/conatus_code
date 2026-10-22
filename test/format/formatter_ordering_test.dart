/// formatter 与 linter 的装配顺序：formatter 内层先跑。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'support/format_harness.dart';

void main() {
  test('formatter 先格式化，linter 后看到格式化后的结果', () async {
    final Directory dir = createProject('mw-order', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final Context app = Context.root();
    provideTools(app);
    final RecordingShell shell = RecordingShell(
      (String command) => command.startsWith('dart format')
          ? okResult()
          : const ShellRunResult(
              exitCode: 0,
              timedOut: false,
              timeoutMs: 30000,
              stdout: CollectedOutput(text: ''),
              stderr: CollectedOutput(text: ''),
            ),
    );
    addTearDown(app.dispose);
    // 先 linter（外层），后 formatter（内层）。
    provideLinter(
      app,
      config: const LintConfig(),
      workdir: dir.path,
      shell: shell,
    );
    provideFormatter(
      app,
      config: const FormatterConfig(enabled: true),
      workdir: dir.path,
      shell: shell,
    );
    registerWriteFile(app);

    final ToolResult result = await app.tools.call(
      const ToolCall(
        name: 'write_file',
        arguments: <String, Object?>{'path': 'lib/a.dart'},
      ),
    );
    expect(result.isError, isFalse);
    expect(shell.commands, hasLength(2));
    expect(shell.commands[0], startsWith('dart format'));
    expect(shell.commands[1], startsWith('dart analyze'));
  });
}

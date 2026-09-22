import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import '../fs_tools/support/fake_shell.dart';

ToolContext _context(String name, Map<String, Object?> args) =>
    ToolContext(ToolCall(name: name, arguments: args));

ShellRunResult _run({
  int? exitCode = 0,
  bool timedOut = false,
  String stdout = '',
  String stderr = '',
}) =>
    ShellRunResult(
      exitCode: exitCode,
      timedOut: timedOut,
      timeoutMs: 20000,
      stdout: CollectedOutput(text: stdout),
      stderr: CollectedOutput(text: stderr),
    );

void main() {
  group('GitStatusTool', () {
    test('有改动时输出行并标记 clean=false', () async {
      final FakeShellExecutor shell = FakeShellExecutor(
          _run(stdout: '## master\n M lib/a.dart\n?? new.dart\n'));
      final GitStatusTool tool = GitStatusTool(shell: shell);

      final ToolResult result = await tool.call(_context('git_status', <String, Object?>{}));

      expect(result.isError, isFalse);
      expect(result.content, contains(' M lib/a.dart'));
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['clean'], isFalse);
      expect(value['changed'], 2);
      expect(shell.lastRequest!.command, 'git --no-pager status --porcelain --branch');
    });

    test('干净时输出工作区干净', () async {
      final FakeShellExecutor shell =
          FakeShellExecutor(_run(stdout: '## master\n'));
      final GitStatusTool tool = GitStatusTool(shell: shell);

      final ToolResult result = await tool.call(_context('git_status', <String, Object?>{}));

      expect(result.isError, isFalse);
      expect(result.content, '工作区干净');
      expect((result.value! as Map<String, Object?>)['clean'], isTrue);
    });

    test('非零退出带 stderr 映射为 GIT_ERROR', () async {
      final FakeShellExecutor shell =
          FakeShellExecutor(_run(exitCode: 128, stderr: 'fatal: not a git repository\n'));
      final GitStatusTool tool = GitStatusTool(shell: shell);

      final ToolResult result = await tool.call(_context('git_status', <String, Object?>{}));

      expect(result.isError, isTrue);
      expect(result.error?.code, 'GIT_ERROR');
      expect(result.content, contains('not a git repository'));
    });

    test('超时映射为 GIT_TIMEOUT', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run(timedOut: true));
      final GitStatusTool tool = GitStatusTool(shell: shell);

      final ToolResult result = await tool.call(_context('git_status', <String, Object?>{}));

      expect(result.isError, isTrue);
      expect(result.error?.code, 'GIT_TIMEOUT');
    });
  });

  group('GitDiffTool', () {
    test('有差异时原样输出', () async {
      final FakeShellExecutor shell = FakeShellExecutor(
          _run(stdout: 'diff --git a/lib/a.dart b/lib/a.dart\nindex 000..111\n'));
      final GitDiffTool tool = GitDiffTool(shell: shell);

      final ToolResult result =
          await tool.call(_context('git_diff', <String, Object?>{}));

      expect(result.isError, isFalse);
      expect(result.content, startsWith('diff --git'));
      expect(shell.lastRequest!.command, 'git --no-pager diff --');
    });

    test('staged 与 path 与 context 拼进命令，路径加引号', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run());
      final GitDiffTool tool = GitDiffTool(shell: shell);

      await tool.call(_context('git_diff', <String, Object?>{
        'staged': true,
        'path': 'lib/my file.dart',
        'context': 5,
      }));

      expect(shell.lastRequest!.command,
          "git --no-pager diff --staged -U 5 -- 'lib/my file.dart'");
    });

    test('无差异输出空结果', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run());
      final GitDiffTool tool = GitDiffTool(shell: shell);

      final ToolResult result =
          await tool.call(_context('git_diff', <String, Object?>{}));

      expect(result.isError, isFalse);
      expect(result.content, '无差异');
      expect((result.value! as Map<String, Object?>)['empty'], isTrue);
    });
  });
}

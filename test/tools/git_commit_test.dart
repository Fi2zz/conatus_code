/// GitCommitTool：git commit 的消息转义、body 拼接与失败映射。
library;

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
      timeoutMs: 30000,
      stdout: CollectedOutput(text: stdout),
      stderr: CollectedOutput(text: stderr),
    );

void main() {
  test('提交成功：透传 git 输出，消息含空格与引号时正确转义', () async {
    final FakeShellExecutor shell = FakeShellExecutor(
      _run(stdout: '[master 1a2b3c4] feat(code): 新增 /commit 命令\n'),
    );
    final GitCommitTool tool = GitCommitTool(shell: shell);

    final ToolResult result = await tool.call(_context('git_commit', <String, Object?>{
      'message': "feat(code): 新增 '引号' 与 空格 描述",
    }));

    expect(result.isError, isFalse);
    expect(result.content, contains('1a2b3c4'));
    expect(
      shell.lastRequest!.command,
      contains(r"commit -m 'feat(code): 新增 '\''引号'\'' 与 空格 描述'"),
    );
  });

  test('body 经第二个 -m 传入', () async {
    final FakeShellExecutor shell = FakeShellExecutor(_run(stdout: 'done'));
    final GitCommitTool tool = GitCommitTool(shell: shell);

    await tool.call(_context('git_commit', <String, Object?>{
      'message': 'fix(a): 修复',
      'body': '详情正文',
    }));

    expect(
      shell.lastRequest!.command,
      contains("-m 'fix(a): 修复' -m '详情正文'"),
    );
  });

  test('非零退出 → 失败映射含 stderr', () async {
    final FakeShellExecutor shell = FakeShellExecutor(_run(
      exitCode: 1,
      stderr: 'error: 没有已暂存的改动',
    ));
    final GitCommitTool tool = GitCommitTool(shell: shell);

    final ToolResult result = await tool.call(_context('git_commit', <String, Object?>{
      'message': 'feat(x): 空提交',
    }));

    expect(result.isError, isTrue);
    expect(result.error?.code, 'GIT_ERROR');
    expect(result.content, contains('没有已暂存的改动'));
  });

  test('超时 → GIT_TIMEOUT', () async {
    final FakeShellExecutor shell = FakeShellExecutor(_run(timedOut: true));
    final GitCommitTool tool = GitCommitTool(shell: shell);

    final ToolResult result = await tool.call(_context('git_commit', <String, Object?>{
      'message': 'feat(x): 慢',
    }));

    expect(result.isError, isTrue);
    expect(result.error?.code, 'GIT_TIMEOUT');
  });

  test('缺 message 参数报错', () async {
    final GitCommitTool tool =
        GitCommitTool(shell: FakeShellExecutor(_run()));
    await expectLater(
      tool.call(_context('git_commit', <String, Object?>{})),
      throwsA(isA<ToolArgumentException>()),
    );
  });
}

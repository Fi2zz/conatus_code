/// git 写操作工具：参数拼装、风险分级、缺参保护。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import '../fs_tools/support/fake_shell.dart';

/// 装好 provideCodeTools 依赖的最小上下文。
Context wiredCodeTools() {
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  provideTools(ctx);
  provideFileSystemLocal(ctx);
  provideShellLocal(ctx);
  provideCodeTools(ctx);
  return ctx;
}

ToolContext _context(String name, Map<String, Object?> args) =>
    ToolContext(ToolCall(name: name, arguments: args));

ShellRunResult _run({
  int exitCode = 0,
  String stdout = '',
  String stderr = '',
}) => ShellRunResult(
  exitCode: exitCode,
  timedOut: false,
  timeoutMs: 20000,
  stdout: CollectedOutput(text: stdout),
  stderr: CollectedOutput(text: stderr),
);

void main() {
  group('gitQuote', () {
    test('单引号按 POSIX 转义', () {
      expect(gitQuote('a b'), "'a b'");
      expect(gitQuote("it's"), "'it'\\''s'");
    });
  });

  group('GitAddTool', () {
    test('列路径时只暂存这些路径', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run());
      final ToolResult result = await GitAddTool(shell: shell).call(
        _context('git_add', <String, Object?>{
          'paths': <Object?>['lib/a.dart', 'lib/b.dart'],
        }),
      );

      expect(result.isError, isFalse);
      expect(
        shell.lastRequest!.command,
        "git --no-pager add -- 'lib/a.dart' 'lib/b.dart'",
      );
    });

    test('all=true 走 add -A（含删除）', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run());
      await GitAddTool(
        shell: shell,
      ).call(_context('git_add', <String, Object?>{'all': true}));
      expect(shell.lastRequest!.command, 'git --no-pager add -A');
    });

    // 缺参时若默认全量暂存，模型一次手滑就会把整个仓库扫进去。
    test('既没 all 也没 paths：报错而不是全量暂存', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run());
      final ToolResult result = await GitAddTool(
        shell: shell,
      ).call(_context('git_add', <String, Object?>{}));

      expect(result.isError, isTrue);
      expect(result.content, contains('all=true'));
      expect(shell.calls, 0, reason: '不该真的调 git');
    });

    test('路径带空格也安全', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run());
      await GitAddTool(shell: shell).call(
        _context('git_add', <String, Object?>{
          'paths': <Object?>['my file.txt'],
        }),
      );
      expect(shell.lastRequest!.command, contains("'my file.txt'"));
    });

    // medium 而非 high：默认 askWhenNeeded 卡在 high 阈值，high 会让每次提交
    // 都弹审批框——而暂存是可逆的（git restore --staged）。
    test('风险是 medium（默认模式不拦）', () {
      expect(
        GitAddTool(shell: FakeShellExecutor(_run())).riskLevel,
        ToolRisk.medium,
      );
    });

    test('git 非零退出转失败', () async {
      final FakeShellExecutor shell = FakeShellExecutor(
        _run(exitCode: 1, stderr: 'fatal: pathspec'),
      );
      final ToolResult result = await GitAddTool(
        shell: shell,
      ).call(_context('git_add', <String, Object?>{'all': true}));
      expect(result.isError, isTrue);
      expect(result.content, contains('fatal: pathspec'));
    });
  });

  group('GitBranchTool', () {
    test('create=true 走 checkout -b', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run());
      final ToolResult result = await GitBranchTool(shell: shell).call(
        _context('git_branch', <String, Object?>{
          'name': 'feat/x',
          'create': true,
        }),
      );

      expect(shell.lastRequest!.command, "git --no-pager checkout -b 'feat/x'");
      expect(result.content, contains('已创建'));
    });

    test('不带 create 是切换', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run());
      await GitBranchTool(
        shell: shell,
      ).call(_context('git_branch', <String, Object?>{'name': 'main'}));
      expect(shell.lastRequest!.command, "git --no-pager checkout 'main'");
    });

    test('list=true 只读，不切分支', () async {
      final FakeShellExecutor shell = FakeShellExecutor(
        _run(stdout: '* main\n  feat/x\n'),
      );
      final ToolResult result = await GitBranchTool(
        shell: shell,
      ).call(_context('git_branch', <String, Object?>{'list': true}));

      expect(shell.lastRequest!.command, 'git --no-pager branch --list');
      expect(result.content, contains('feat/x'));
    });

    // 切分支丢工作区改动是开发里最贵的误操作，不该由模型来点。
    test('没有 reset --hard / -C 之类的强制重置入口', () {
      const List<String> names = <String>['reset', 'hard', 'force', 'clean'];
      final List<String> params = GitBranchTool(
        shell: FakeShellExecutor(_run()),
      ).params.map((ParamSpec p) => p.name).toList();
      for (final String bad in names) {
        expect(params.contains(bad), isFalse, reason: bad);
      }
    });
  });

  group('GitStashTool', () {
    test('缺省 pop', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run());
      await GitStashTool(
        shell: shell,
      ).call(_context('git_stash', <String, Object?>{}));
      expect(shell.lastRequest!.command, 'git --no-pager stash pop');
    });

    test('keep=true 收进但保留条目', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run());
      await GitStashTool(
        shell: shell,
      ).call(_context('git_stash', <String, Object?>{'keep': true}));
      expect(shell.lastRequest!.command, 'git --no-pager stash push');
    });

    test('keep + message 带上说明', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run());
      await GitStashTool(shell: shell).call(
        _context('git_stash', <String, Object?>{
          'keep': true,
          'message': '调试一半',
        }),
      );
      expect(shell.lastRequest!.command, contains("-m '调试一半'"));
    });

    test('restore=true 只列 stash', () async {
      final FakeShellExecutor shell = FakeShellExecutor(
        _run(stdout: 'stash@{0}: WIP on main'),
      );
      final ToolResult result = await GitStashTool(
        shell: shell,
      ).call(_context('git_stash', <String, Object?>{'restore': true}));
      expect(shell.lastRequest!.command, 'git --no-pager stash list');
      expect(result.content, contains('stash@{0}'));
    });

    test('风险是 medium', () {
      expect(
        GitStashTool(shell: FakeShellExecutor(_run())).riskLevel,
        ToolRisk.medium,
      );
    });
  });

  group('provideCodeTools 注册', () {
    test('六个 git 工具都在表里', () {
      final Context ctx = wiredCodeTools();

      for (final String name in <String>[
        'git_status',
        'git_diff',
        'git_add',
        'git_branch',
        'git_stash',
        'git_commit',
      ]) {
        expect(ctx.tools.get(name), isNotNull, reason: name);
      }
    });

    test('只有 commit 是 high，其余 git 工具不触发默认审批', () {
      final Context ctx = wiredCodeTools();

      expect(ctx.tools.get('git_commit')!.riskLevel, ToolRisk.high);
      for (final String name in <String>[
        'git_add',
        'git_branch',
        'git_stash',
      ]) {
        expect(ctx.tools.get(name)!.riskLevel, ToolRisk.medium, reason: name);
      }
    });
  });
}

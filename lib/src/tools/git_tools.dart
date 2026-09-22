import 'package:conatus_foundation/conatus_foundation.dart';

/// 单次只读 git 命令的输出上限（字节）。
const int _maxOutputBytes = 1024 * 1024;

/// 只读 git 命令的执行结果。
class GitRun {
  /// 成功：携带 stdout。
  const GitRun.text(this.text) : failure = null;

  /// 失败：携带现成的失败结果。
  const GitRun.failure(this.failure) : text = '';

  /// 命令 stdout（失败时为空串）。
  final String text;

  /// 失败结果（成功时为 `null`）。
  final ToolResult? failure;
}

/// 执行只读 git 命令：禁用分页器、限时、限输出，非零退出转成失败结果。
///
/// 走 `shell` 接缝，因此与 rg 受同一套命令策略约束（M3 起同受沙箱约束）。
Future<GitRun> runGit(ShellExecutor shell, String args, Duration timeout) async {
  final ShellExecSpec spec = shell.resolve(ShellExecRequest(
    command: 'git --no-pager $args',
    timeoutMs: timeout.inMilliseconds,
    stdoutMaxBytes: _maxOutputBytes,
  ));
  final ShellRunResult result = await shell.run(spec);
  if (result.timedOut) {
    return GitRun.failure(ToolResult.failure('git 执行超时',
        error: const ToolError('GIT_TIMEOUT', 'timeout')));
  }
  if (result.exitCode != 0) {
    final String message = result.stderr.text.trim();
    return GitRun.failure(ToolResult.failure(
      message.isEmpty ? 'git 退出码 ${result.exitCode}' : message,
      error: ToolError('GIT_ERROR', message),
    ));
  }
  return GitRun.text(result.stdout.text);
}

/// 查看分支与工作区改动（`git status --porcelain --branch`）。只读。
class GitStatusTool extends Tool {
  const GitStatusTool({
    required ShellExecutor shell,
    this.timeout = const Duration(seconds: 20),
  }) : _shell = shell;

  final ShellExecutor _shell;

  @override
  final Duration? timeout;

  @override
  String get name => 'git_status';

  @override
  String get description => '查看当前分支与工作区改动（git status --porcelain --branch）。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final GitRun run = await runGit(_shell, 'status --porcelain --branch', timeout!);
    final ToolResult? failure = run.failure;
    if (failure != null) return failure;
    final List<String> lines = _lines(run.text);
    final int changed = lines.where((String l) => !l.startsWith('##')).length;
    if (changed == 0) {
      return ToolResult.success('工作区干净', value: <String, Object?>{'clean': true});
    }
    return ToolResult.success(lines.join('\n'),
        value: <String, Object?>{'clean': false, 'changed': changed});
  }

  List<String> _lines(String text) => <String>[
        for (final String line in text.split('\n'))
          if (line.trimRight().isNotEmpty) line.trimRight(),
      ];
}

/// 查看未提交差异（`git diff`）。只读。
class GitDiffTool extends Tool {
  const GitDiffTool({
    required ShellExecutor shell,
    this.timeout = const Duration(seconds: 30),
  }) : _shell = shell;

  final ShellExecutor _shell;

  @override
  final Duration? timeout;

  @override
  String get name => 'git_diff';

  @override
  String get description => '查看未提交的代码差异；staged 为 true 时只看已暂存部分。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('path', description: '限定路径'),
        ParamSpec.boolean('staged', description: '只看已暂存（--staged）'),
        ParamSpec.integer('context', description: '上下文行数，默认 3'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final GitRun run = await runGit(_shell, _args(ctx), timeout!);
    final ToolResult? failure = run.failure;
    if (failure != null) return failure;
    final String text = run.text.trimRight();
    if (text.isEmpty) {
      return ToolResult.success('无差异', value: <String, Object?>{'empty': true});
    }
    return ToolResult.success(text, value: <String, Object?>{
      'empty': false,
      'lines': text.split('\n').length,
    });
  }

  String _args(ToolContext ctx) {
    final List<String> parts = <String>['diff'];
    if (ctx.optional<bool>('staged') ?? false) parts.add('--staged');
    if (ctx.has('context')) parts.addAll(<String>['-U', '${ctx.integer('context')}']);
    parts.add('--');
    if (ctx.has('path')) parts.add(_quote(ctx.str('path')));
    return parts.join(' ');
  }

  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}

/// git 的写操作工具：暂存 / 分支 / 藏匿。
///
/// 此前只有 `git_status` / `git_diff` / `git_commit` 三个只读+提交工具，于是
/// `/commit` 的提示词让模型「向用户说明并给出建议（如先 git add 暂存）」——
/// nava 把一个例行步骤推回给了用户。模型想自己暂存只能走 `run_command`，而它是
/// `ToolRisk.high`，默认 `askWhenNeeded` 模式正好卡在 high 阈值上，于是每次提交
/// 都要弹一次审批框。
///
/// 风险分级：`git add` / `git_stash` 只动索引与工作区快照，不产生不可逆的
/// 历史，故 medium（默认模式不拦）；`git checkout -b` 建分支同样是 medium——它
/// 不丢数据。**没有任何一个工具会丢工作**（无 `reset --hard` / `clean` /
/// `push --force`），丢数据的操作留给用户自己在终端里做。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'git_tools.dart';

/// 暂存改动（`git add`）。
///
/// 传 `all: true` 等价 `git add -A`（含删除）。**不含** `git add .` 的隐式
/// 全量语义——默认只暂存明确列出的路径，避免模型顺手把整个仓库扫进去。
class GitAddTool extends Tool {
  const GitAddTool({
    required ShellExecutor shell,
    this.timeout = const Duration(seconds: 20),
  }) : _shell = shell;

  final ShellExecutor _shell;

  @override
  final Duration? timeout;

  @override
  String get name => 'git_add';

  @override
  String get description =>
      '把改动加入暂存区（git add），为 git_commit 做准备。'
      '传 all=true 暂存全部改动（含删除）；否则只暂存 paths 里列出的路径。';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  List<ParamSpec> get params => <ParamSpec>[
    ParamSpec.array(
      'paths',
      items: ParamSpec.string('item'),
      description: '要暂存的路径（相对仓库根）；all=true 时可省略',
    ),
    ParamSpec.boolean('all', description: '暂存全部改动（含删除，等价 git add -A）'),
  ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final bool all = ctx.optional<bool>('all') ?? false;
    final List<String> paths = <String>[
      for (final Object? p in ctx.array('paths') ?? const <Object?>[]) '$p',
    ];
    if (!all && paths.isEmpty) {
      return ToolResult.failure(
        '要暂存全部改动请传 all=true，或在 paths 里列出路径。',
        error: const ToolError('GIT_NO_PATHS', 'no-paths'),
      );
    }
    final String args = all
        ? 'add -A'
        : 'add -- ${paths.map(gitQuote).join(' ')}';
    final GitRun run = await runGit(_shell, args, timeout!);
    final ToolResult? failure = run.failure;
    if (failure != null) return failure;
    return ToolResult.success('已暂存 ${all ? '全部改动' : '${paths.length} 个路径'}。');
  }
}

/// 建分支或切换分支（`git checkout -b` / `git checkout`）。
///
/// **不提供** `git switch -C` 之类的强制重置：切分支丢工作区改动是开发里最贵
/// 的误操作之一，不该由模型来点。
class GitBranchTool extends Tool {
  const GitBranchTool({
    required ShellExecutor shell,
    this.timeout = const Duration(seconds: 20),
  }) : _shell = shell;

  final ShellExecutor _shell;

  @override
  final Duration? timeout;

  @override
  String get name => 'git_branch';

  @override
  String get description =>
      '建新分支（create=true）或切换已有分支（git checkout）。'
      '不带 create 时切到已存在的分支。有未提交改动时 git 会拒绝切换。';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  List<ParamSpec> get params => <ParamSpec>[
    ParamSpec.string('name', required: true, description: '分支名'),
    ParamSpec.boolean('create', description: '创建新分支（等价 git checkout -b）'),
    ParamSpec.boolean('list', description: '只列出本地分支，不做任何改动'),
  ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    if (ctx.optional<bool>('list') ?? false) {
      final GitRun run = await runGit(_shell, 'branch --list', timeout!);
      final ToolResult? failure = run.failure;
      if (failure != null) return failure;
      return ToolResult.success(
        run.text.trim().isEmpty ? '（无分支）' : run.text.trim(),
      );
    }
    final String name = ctx.str('name');
    final bool create = ctx.optional<bool>('create') ?? false;
    final String args = create
        ? 'checkout -b ${gitQuote(name)}'
        : 'checkout ${gitQuote(name)}';
    final GitRun run = await runGit(_shell, args, timeout!);
    final ToolResult? failure = run.failure;
    if (failure != null) return failure;
    return ToolResult.success(create ? '已创建并切到 $name。' : '已切到 $name。');
  }
}

/// 暂存 / 恢复工作区改动（`git stash`）。
///
/// 缺省 `pop=true`（取出最近一条）。`keep=true` 保留 stash 条目不删。
class GitStashTool extends Tool {
  const GitStashTool({
    required ShellExecutor shell,
    this.timeout = const Duration(seconds: 20),
  }) : _shell = shell;

  final ShellExecutor _shell;

  @override
  final Duration? timeout;

  @override
  String get name => 'git_stash';

  @override
  String get description =>
      '把未提交改动收进 stash（临时搁置），或取回。'
      '默认 pop（取出最近一条并从 stash 列表移除）；'
      'keep=true 收进 stash 但保留条目；restore=true 只列出 stash。';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  List<ParamSpec> get params => <ParamSpec>[
    ParamSpec.boolean('restore', description: '只列出 stash 条目，不做改动'),
    ParamSpec.boolean('keep', description: '收进 stash 但保留条目（不 pop）'),
    ParamSpec.string('message', description: '给这次 stash 加的说明（仅收进时用）'),
  ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final bool restore = ctx.optional<bool>('restore') ?? false;
    if (restore) {
      final GitRun run = await runGit(_shell, 'stash list', timeout!);
      final ToolResult? failure = run.failure;
      if (failure != null) return failure;
      return ToolResult.success(
        run.text.trim().isEmpty ? '（stash 为空）' : run.text.trim(),
      );
    }
    final bool keep = ctx.optional<bool>('keep') ?? false;
    final String? message = ctx.string('message');
    final String args = keep
        ? message == null
              ? 'stash push'
              : 'stash push -m ${gitQuote(message)}'
        : 'stash pop';
    final GitRun run = await runGit(_shell, args, timeout!);
    final ToolResult? failure = run.failure;
    if (failure != null) return failure;
    final String text = run.text.trim();
    return ToolResult.success(
      text.isEmpty ? (keep ? '已收进 stash。' : '已取出最近一条 stash。') : text,
    );
  }
}

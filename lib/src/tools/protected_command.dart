/// `.opencode` 命令级兜底：字面识别「路径段 + 写类操作符」。
///
/// **这只是 best-effort**，不是安全边界：变量拼接、`sh -c "$CMD"`、读脚本
/// 再执行、`eval` 等都能绕过。它覆盖命令工具那条路径上能被字面识别的写法，
/// 与 fs 侧的同名闸门（见 `read_only_policy.dart`）共用文案。
///
/// 覆盖两个目录：项目级 `.opencode` 与全局 `~/.config/opencode`
/// （`rm -rf ~/.config/opencode` 同样必须拒）。
///
/// 保守取舍：宁可误拒（例如 `cat .opencode/x > out.txt` 也被拒），也不放过
/// 明显的写入形态。
library;

import '../read_only_policy.dart';

/// 错误码（与 fs 闸门的 `FsErrorCode.permissionDenied` 同一文案体系）。
const String kReadOnlyCommandCode = kReadOnlyPathCode;

/// 拒绝信息，与 fs 闸门共用同一文案。
const String kReadOnlyCommandMessage = kReadOnlyPathMessage;

/// 命令字面命中「受保护目录 + 写类操作符」时返回拒绝信息，否则 null。
String? readOnlyCommandViolation(String command) {
  if (!_mentionsProtectedSegment(command)) return null;
  if (!_looksWrite(command)) return null;
  return kReadOnlyCommandMessage;
}

/// 去掉引号与反斜杠后按「路径段边界」匹配两个受保护目录。
///
/// 覆盖 `.opencode/x`、`x/.opencode`、`>.opencode/x`、`--path=.opencode/x`、
/// `~/.config/opencode`、`$HOME/.config/opencode` 等写法；
/// `.opencode-backup`、`my.opencode.txt` 不算。
bool _mentionsProtectedSegment(String command) {
  final String flat = command.replaceAll(RegExp(r'''["'`\\]'''), ' ');
  return _projectSegment.hasMatch(flat) || _globalSegment.hasMatch(flat);
}

/// 项目级 `.opencode` 段；大小写不敏感（APFS 上 `.OPENCODE` 是同一目录）。
final RegExp _projectSegment = RegExp(
  r'(^|[\s=:;,()<>|&/])\.opencode($|[\s=:;,()<>|&/])',
  caseSensitive: false,
);

/// 全局 `.../.config/opencode`（`~`、`$HOME` 或绝对路径拼写）。
final RegExp _globalSegment = RegExp(
  r'(^|[\s=:;,()<>|&/])\.config/opencode($|[\s=:;,()<>|&/])',
  caseSensitive: false,
);

/// 写类操作符 / 命令：重定向、tee、rm、mv、cp、sed -i、truncate、touch……
final RegExp _writeOps = RegExp(
  r'(>>?|\btee\b|\brm\b|\bmv\b|\bcp\b|\bsed\s+-i|\btruncate\b|\btouch\b|'
  r'\bmkdir\b|\bln\b|\bchmod\b|\bdd\b|\binstall\b)',
);

bool _looksWrite(String command) => _writeOps.hasMatch(command);

/// git 写子命令对 `.opencode` 的兜底拒绝（`runGit` 用）。
///
/// git 写工具（`git_add` / `git_commit` / `git_branch` / `git_stash`）经
/// `runGit` 直接拼 argv，不经过 `bash` 的命令检查；`git checkout
/// .opencode/x` 之类的操作会真的写用户只读目录。这里按「子命令 + 非选项操作数
/// 里的受保护路径段」判定，跳过 `-m` 的消息文本（`git commit -m "fix
/// .opencode"` 不该被误拒）。
String? gitWriteViolation(String args) {
  final List<String> tokens = _commandTokens(args);
  if (tokens.isEmpty || !_gitWriteSubcommands.contains(tokens.first)) {
    return null;
  }
  for (int index = 1; index < tokens.length; index++) {
    final String token = tokens[index];
    if (token == '-m' || token == '--message') {
      index++; // 消息正文不是路径
      continue;
    }
    if (token.startsWith('-')) continue;
    if (_mentionsProtectedSegment(token)) return kReadOnlyPathMessage;
  }
  return null;
}

/// 会改写工作区 / 索引的 git 子命令（`commit` 的路径参数只影响提交内容，
/// 不改受保护目录，故不列入）。
const Set<String> _gitWriteSubcommands = <String>{
  'add',
  'rm',
  'mv',
  'checkout',
  'restore',
  'reset',
  'clean',
  'stash',
  'apply',
  'am',
  'merge',
  'rebase',
  'cherry-pick',
  'revert',
  'pull',
};

/// 按单引号 / 双引号切分命令行（不处理嵌套引号；git 工具只用单引号）。
List<String> _commandTokens(String args) {
  final List<String> out = <String>[];
  final StringBuffer current = StringBuffer();
  bool quoted = false;
  for (int index = 0; index < args.length; index++) {
    final String char = args[index];
    if (char == "'" || char == '"') {
      quoted = !quoted;
      continue;
    }
    if (char == ' ' && !quoted) {
      if (current.isNotEmpty) {
        out.add(current.toString());
        current.clear();
      }
      continue;
    }
    current.write(char);
  }
  if (current.isNotEmpty) out.add(current.toString());
  return out;
}

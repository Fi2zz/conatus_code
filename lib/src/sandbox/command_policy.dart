/// 命令策略：command_shield 语义分析 + 可执行白名单 + 越界路径检查。
library;

import 'dart:io';

import 'package:command_shield/command_shield.dart' as shield;

/// 命令策略的裁决。
enum CommandDecision { allow, deny, review }

/// 一次裁决的结果：决策与理由。
class CommandVerdict {
  const CommandVerdict(this.decision, this.reason);

  final CommandDecision decision;
  final String reason;
}

/// 命令策略：先经 command_shield 判 allow/review/deny，再自查可执行白名单
/// 与越界路径。任一层不通过即拒绝；仅全部通过才放行。
class CommandPolicy {
  CommandPolicy({
    required this.root,
    Set<String>? allowedExecutables,
    Set<String>? readAllowedPaths,
    shield.CommandShield? shieldImpl,
  }) : _allowedExecutables = allowedExecutables ?? _defaultExecutables,
       _readAllowed = _buildReadAllowed(readAllowedPaths),
       _shield =
           shieldImpl ?? shield.CommandShield(defaultSyntax: shield.CommandSyntax.bash);

  /// 沙箱根（规范化）。
  final String root;

  final Set<String> _allowedExecutables;
  final Set<String> _readAllowed;
  final shield.CommandShield _shield;

  /// 构造只读放行集合：展开 `~`、加入 Dart SDK 根。
  static Set<String> _buildReadAllowed(Set<String>? readAllowedPaths) {
    final String? sdk = _sdkRoot();
    return <String>{
      for (final String raw in readAllowedPaths ?? _defaultReadPaths)
        _normalizeWithHome(raw),
      if (sdk != null) sdk,
    };
  }

  /// 裁决命令；deny/review 附理由。
  CommandVerdict decide(String command) {
    final shield.CommandResult result = _shield.validate(command);
    if (result.decision == shield.CommandDecision.deny) {
      return CommandVerdict(CommandDecision.deny, _findingText(result));
    }
    if (result.decision == shield.CommandDecision.review) {
      return CommandVerdict(CommandDecision.review, _findingText(result));
    }
    return _checkInvocations(command);
  }

  /// 逐个 invocation 查可执行白名单与越界路径。
  CommandVerdict _checkInvocations(String command) {
    final shield.ParseResult parsed = shield.ParserFactory.forSyntax(
        shield.CommandSyntax.bash).parse(command);
    for (final shield.CommandInvocation inv in parsed.invocations) {
      if (!_allowedExecutables.contains(inv.executable)) {
        return CommandVerdict(
            CommandDecision.deny, '可执行文件不在白名单：${inv.executable}');
      }
      final CommandVerdict pathVerdict = _checkPaths(inv);
      if (pathVerdict.decision != CommandDecision.allow) return pathVerdict;
    }
    return const CommandVerdict(CommandDecision.allow, '');
  }

  /// 检查 invocation 的路径字面量是否越界。
  CommandVerdict _checkPaths(shield.CommandInvocation inv) {
    for (final String arg in inv.arguments) {
      if (!_pathLiteral(arg)) continue;
      final String resolved = _resolvePath(arg);
      if (_within(resolved, root)) continue;
      if (_withinReadAllowed(resolved)) continue;
      return CommandVerdict(CommandDecision.deny, '路径越界：$arg');
    }
    return const CommandVerdict(CommandDecision.allow, '');
  }

  /// 是否为可解析的路径字面量（绝对路径或含 `..`）；含变量展开的不判。
  bool _pathLiteral(String arg) {
    if (arg.contains(r'$') || arg.contains('`')) return false;
    if (arg.startsWith('/') || arg.startsWith('~/')) return true;
    if (arg == '..' || arg.startsWith('../')) return true;
    return arg.contains('/../');
  }

  /// 相对 root 解析；`~/` 按 HOME 展开。
  String _resolvePath(String arg) {
    if (arg.startsWith('~/')) {
      final String home = Platform.environment['HOME'] ?? '';
      return _normalize('$home/${arg.substring(2)}');
    }
    return _normalize(arg.startsWith('/') ? arg : '$root/$arg');
  }

  bool _withinReadAllowed(String path) {
    for (final String allowed in _readAllowed) {
      if (_within(path, allowed)) return true;
    }
    return false;
  }

  String _findingText(shield.CommandResult result) {
    if (result.findings.isEmpty) return '命令被策略拦截';
    return result.findings.map((shield.SecurityFinding f) => f.message).join('；');
  }
}

/// 路径是否在 [parent] 之内（含自身）。
bool _within(String path, String parent) =>
    path == parent || path.startsWith('$parent/');String _normalize(String path) => Uri.file(path).normalizePath().toFilePath();

String _normalizeWithHome(String path) {
  if (!path.startsWith('~/')) return _normalize(path);
  final String home = Platform.environment['HOME'] ?? '';
  return _normalize('$home/${path.substring(2)}');
}

/// Dart SDK 根目录：DART_SDK 优先，否则取可执行文件的上级上级。
String? _sdkRoot() {
  final String? sdk = Platform.environment['DART_SDK'];
  if (sdk != null && sdk.isNotEmpty) return sdk;
  final String exe = Platform.resolvedExecutable;
  final int binCut = exe.lastIndexOf('/');
  if (binCut <= 0) return null;
  final int sdkCut = exe.lastIndexOf('/', binCut - 1);
  if (sdkCut <= 0) return null;
  return exe.substring(0, sdkCut);
}

/// 合并缺省可执行白名单与用户扩展项。
///
/// 扩展语义：用户配置只增不减——避免"授权一个工具却静默丢掉全部默认项"。
Set<String> resolveAllowedExecutables(Iterable<String> userProvided) =>
    <String>{
      ..._defaultExecutables,
      for (final String name in userProvided)
        if (name.isNotEmpty) name,
    };

/// 合并缺省只读放行路径与用户扩展项（`writable_paths` 经此进入命令路径裁决）。
Set<String> resolveReadAllowedPaths(Iterable<String> userProvided) =>
    <String>{
      ..._defaultReadPaths,
      for (final String path in userProvided)
        if (path.isNotEmpty) path,
    };

/// 缺省可执行白名单：coding 常用命令集合。
const Set<String> _defaultExecutables = <String>{
  'dart', 'flutter', 'git', 'rg', 'ls', 'cat', 'sed', 'grep',
  'mkdir', 'mv', 'cp', 'rm', 'touch', 'echo', 'pwd', 'find',
  'head', 'tail', 'sort', 'uniq', 'wc', 'sh', 'bash', 'python3', 'node',
};

/// 缺省只读放行路径：系统与工具缓存目录、tmp 真实路径、设备文件（`~`
/// 构造时展开）。与 Seatbelt 可写面保持一致，避免策略层先于 OS 层误拒。
const Set<String> _defaultReadPaths = <String>{
  '~/.pub-cache', '~/.dart_tool', '~/.m2', '~/.gradle',
  '/tmp', '/private/tmp', '/var/tmp', '/private/var/folders',
  '/dev/null', '/dev/zero', '/dev/stdout', '/dev/stderr', '/dev/tty',
};

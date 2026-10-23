/// `.opencode` 只读策略的单一事实来源：目录名、保护根与错误文案。
///
/// fs 闸门（`fs_tools/read_only_path_guard.dart`）、命令兜底
/// （`sandbox/protected_command.dart`）与 Seatbelt 装配
/// （`sandbox/sandbox_assembly.dart`）共用，避免多处各写一份而漂移。
library;

import 'dart:io';

/// 稳定错误码：fs 侧配 [FsErrorCode.permissionDenied]，命令侧作工具错误码。
const String kReadOnlyPathCode = 'READ_ONLY_PATH';

/// 拒绝信息：项目级与全局 OpenCode 目录都只读。
const String kReadOnlyPathMessage =
    'READ_ONLY_PATH: .opencode 目录只读（含 ~/.config/opencode）';

/// 项目内 OpenCode 目录名。
const String kOpenCodeDirName = '.opencode';

/// 全局 OpenCode 目录（`~` 未展开形式，供命令检查 / Seatbelt 解析）。
const String kGlobalOpenCodePath = '~/.config/opencode';

/// Seatbelt 的受保护写路径：项目级用相对形式（由沙箱按 root 解析）。
const List<String> kShellReadOnlyRoots = <String>[
  kOpenCodeDirName,
  kGlobalOpenCodePath,
];

/// 项目级与全局 OpenCode 目录（绝对路径）。
///
/// [home] 缺省取环境变量 `HOME`（再退到 `USERPROFILE`）；相对 [workdir] 按
/// 当前工作目录转绝对。返回的根**不**解析符号链接——调用方在比较时对两侧
/// 都补规范拼写（见 [realPathViaAncestor]），否则「根尚不存在」或「workdir
/// 是别名」时会因拼写不同而漏挡。
List<String> defaultReadOnlyRoots(String workdir, {String? home}) {
  final String sep = Platform.pathSeparator;
  final String? resolvedHome =
      home ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  return <String>[
    normalizeReadOnlyPath('${Directory(workdir).absolute.path}$sep.opencode'),
    if (resolvedHome != null && resolvedHome.isNotEmpty)
      normalizeReadOnlyPath('$resolvedHome$sep.config${sep}opencode'),
  ];
}

/// 段级「相同或子孙」判定：`.opencode-backup` 不算 `.opencode`。
///
/// macOS / Windows 默认文件系统大小写不敏感，统一按小写比较——
/// `.OPENCODE/x` 在 APFS 上就是 `.opencode/x`，不能放过。代价是
/// 大小写敏感卷上会略微多拒（`.OPENCODE` 也会被当成受保护），可接受。
bool underReadOnlyRoot(String path, String root) {
  if (path.isEmpty || root.isEmpty) return false;
  final String candidate = _comparable(path);
  final String base = _comparable(root);
  if (candidate == base) return true;
  final String prefix = base.endsWith(Platform.pathSeparator)
      ? base
      : '$base${Platform.pathSeparator}';
  return candidate.startsWith(prefix);
}

/// 相对路径是否指向 OpenCode 目录（`.opencode` 或 `.config/opencode` 段）。
///
/// 用于「登记时就拒绝」的场景（story 待定补丁、`/init` 目标）：这些路径按
/// 工作区相对写，无法用绝对根比较。任意层级的 `.opencode` 都算（保守）。
bool readOnlyRelativePath(String path) {
  final List<String> segments = path
      .replaceAll('\\', '/')
      .toLowerCase()
      .split('/');
  for (int index = 0; index < segments.length; index++) {
    if (segments[index] == kOpenCodeDirName) return true;
    if (segments[index] == '.config' &&
        index + 1 < segments.length &&
        segments[index + 1] == 'opencode') {
      return true;
    }
  }
  return false;
}

/// 取 [path] 的真实路径：存在则直接解析；否则解析**最近的已存在祖先**
/// 再拼回余下段（与 `fs_local_paths.dart` 的 `_identityViaAncestor` 同法）。
///
/// 受保护根常常尚未创建（用户还没装 `.opencode`），此时整个解析会抛
/// `FileSystemException`；必须退回祖先解析，否则规范拼写为空、闸门 fail-open。
/// 没有任何已存在祖先时返回 null（调用方退回字面拼写）。
String? realPathViaAncestor(String path) {
  final List<String> trailing = <String>[];
  String current = normalizeReadOnlyPath(path);
  while (true) {
    try {
      final String real = Directory(current).resolveSymbolicLinksSync();
      return trailing.isEmpty ? real : _join(real, trailing.reversed);
    } on FileSystemException {
      final int cut = current.lastIndexOf(Platform.pathSeparator);
      if (cut <= 0) return null;
      trailing.add(current.substring(cut + 1));
      current = current.substring(0, cut);
    }
  }
}

/// 去掉冗余的 `.` / `..` 与末尾分隔符（不解析符号链接）。
///
/// Windows 盘符单独保留：`C:\foo` 不能变成 `\C:\foo`（多了前缀分隔符后
/// 既不像绝对路径，也不再与 `Directory(path).absolute.path` 的拼写一致）。
String normalizeReadOnlyPath(String path) {
  final RegExp separators = RegExp(r'[/\\]');
  final String value = path.trim().replaceAll('\\', '/');
  final RegExpMatch? drive = RegExp(r'^([A-Za-z]:)').firstMatch(value);
  final String drivePrefix = drive?.group(1) ?? '';
  final String rest = drivePrefix.isEmpty
      ? value
      : value.substring(drivePrefix.length);
  final bool absolute = rest.startsWith('/');
  final List<String> parts = <String>[];
  for (final String part in rest.split(separators)) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..' && parts.isNotEmpty && parts.last != '..') {
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  final String joined = parts.join(Platform.pathSeparator);
  if (drivePrefix.isNotEmpty) {
    final String separator = Platform.pathSeparator;
    return absolute ? '$drivePrefix$separator$joined' : '$drivePrefix$joined';
  }
  return absolute ? '${Platform.pathSeparator}$joined' : joined;
}

String _comparable(String path) =>
    Platform.isMacOS || Platform.isWindows ? path.toLowerCase() : path;

String _join(String base, Iterable<String> segments) => normalizeReadOnlyPath(
  '$base${Platform.pathSeparator}${segments.join(Platform.pathSeparator)}',
);

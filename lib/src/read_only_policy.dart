/// `.opencode` 只读策略的单一事实来源：目录名、保护根与错误文案。
///
/// 通用闸门（`ReadOnlyPathGuard`）与路径判定在 `conatus_foundation`；
/// 这里只保留 nava 的产品策略：哪些目录只读、按工作区相对路径如何识别。
/// fs 闸门装配与命令兜底（`tools/protected_command.dart`）共用本文件，
/// 避免多处各写一份而漂移。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

/// 稳定错误码：fs 侧配 [FsErrorCode.permissionDenied]，命令侧作工具错误码。
const String kReadOnlyPathCode = 'READ_ONLY_PATH';

/// 拒绝信息：项目级与全局 OpenCode 目录都只读。
const String kReadOnlyPathMessage =
    'READ_ONLY_PATH: .opencode 目录只读（含 ~/.config/opencode）';

/// 项目内 OpenCode 目录名。
const String kOpenCodeDirName = '.opencode';

/// 全局 OpenCode 目录（`~` 未展开形式，供命令检查解析）。
const String kGlobalOpenCodePath = '~/.config/opencode';

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

/// 待写入路径是否命中只读的 OpenCode 目录。
///
/// 判定三种拼写，任一命中即拒绝：
/// - 字面绝对路径（`--config .opencode/config.toml`、`NAVA_HOME=.opencode`）；
/// - 最近已存在祖先解析后的真实路径（父目录是符号链接指向 `.opencode`）；
/// - 与 [defaultReadOnlyRoots] 的字面 / 真实拼写做段级比较。
///
/// 必须在任何 `createSync` / 写盘之前调用：受保护目录可能尚不存在，先创建
/// 就已经晚了。
bool readOnlyWritePath(String path, {String? workdir, String? home}) {
  final String literal = File(path).absolute.path;
  if (readOnlyRelativePath(literal)) return true;
  final String? real = realPathViaAncestor(literal);
  if (real != null && readOnlyRelativePath(real)) return true;
  final List<String> roots = defaultReadOnlyRoots(
    workdir ?? Directory.current.path,
    home: home,
  );
  for (final String root in roots) {
    if (underReadOnlyRoot(literal, root)) return true;
    final String? realRoot = realPathViaAncestor(root);
    if (real != null && realRoot != null && underReadOnlyRoot(real, realRoot)) {
      return true;
    }
  }
  return false;
}

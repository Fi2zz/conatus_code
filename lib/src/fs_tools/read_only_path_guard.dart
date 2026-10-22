/// `.opencode` 只读闸门：`FileSystem` 装饰器，写/删在受保护根下一律拒绝。
///
/// OpenCode 的 `.opencode/**`（项目级）与 `~/.config/opencode/**`（全局）属于
/// 用户自己的安装：nava 只是兼容读取方，绝不创建 / 写入 / 删除 / 改权限。
/// 闸门包在 `'fs'` 接缝上，write_file / edit_file / apply_patch / story 写回
/// 等一切经 fs 的写操作自动继承；读操作全部透传。
///
/// 判定同时看两种拼写：`inner.processPath`（已解析符号链接的规范路径）与
/// `target.displayPath`（字面路径）。前者让别名 / 符号链接下的真实位置参与
/// 比较，后者挡住「`.opencode` 下的链接指向外部」——任一命中即拒绝，
/// fail-closed。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

/// 拒绝信息（配 [FsErrorCode.permissionDenied] 回给模型）。
const String kReadOnlyPathMessage = 'READ_ONLY_PATH: .opencode 目录只读';

/// 项目级与全局 OpenCode 目录（绝对路径）。[home] 缺省取环境变量 `HOME`
/// （再退到 `USERPROFILE`）；相对 [workdir] 按当前工作目录转绝对。
List<String> defaultReadOnlyRoots(String workdir, {String? home}) {
  final String sep = Platform.pathSeparator;
  final String? resolvedHome =
      home ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  return <String>[
    _normalize('${Directory(workdir).absolute.path}$sep.opencode'),
    if (resolvedHome != null && resolvedHome.isNotEmpty)
      _normalize('$resolvedHome$sep.config${sep}opencode'),
  ];
}

/// 把写/删限制在受保护根之外的 [FileSystem] 装饰器。
///
/// 只对本地式后端有意义：判定以绝对路径做段级前缀比较，非文件后端的
/// displayPath 不会命中受保护根，因此自然透传。
class ReadOnlyPathGuard implements FileSystem {
  /// 用被装饰的 [inner] 与受保护根 [protectedRoots] 构造。
  ReadOnlyPathGuard({required this.inner, required List<String> protectedRoots})
    : protectedRoots = <String>[
        for (final String root in protectedRoots)
          if (root.trim().isNotEmpty) _normalize(Directory(root).absolute.path),
      ];

  /// 实际执行 I/O 的后端。
  final FileSystem inner;

  /// 只读根（绝对路径，段级前缀匹配）。
  final List<String> protectedRoots;

  @override
  Future<FsTarget> resolve(String path, {String? cwd}) =>
      inner.resolve(path, cwd: cwd);

  @override
  String processPath(FsTarget target) => inner.processPath(target);

  @override
  String fileUrl(FsTarget target) => inner.fileUrl(target);

  @override
  bool contains(FsTarget parent, FsTarget child) =>
      inner.contains(parent, child);

  @override
  Future<FsInfo?> stat(FsTarget target) => inner.stat(target);

  @override
  Future<FsPathInfo?> lstat(String path, {String? cwd}) =>
      inner.lstat(path, cwd: cwd);

  @override
  Future<String> readText(FsTarget target) => inner.readText(target);

  @override
  Future<List<FsDirEntry>> listDir(FsTarget target) => inner.listDir(target);

  @override
  Future<FsWriteOutcome> writeText(
    FsTarget target,
    String content, {
    FsWriteIntent? expected,
  }) {
    _denyIfProtected(target);
    return inner.writeText(target, content, expected: expected);
  }

  @override
  Future<FsEditOutcome> editText(
    FsTarget target,
    FsEditRequest edit, {
    String? expectedVersion,
  }) {
    _denyIfProtected(target);
    return inner.editText(target, edit, expectedVersion: expectedVersion);
  }

  @override
  Future<void> remove(FsTarget target) {
    _denyIfProtected(target);
    return inner.remove(target);
  }

  /// 命中任一受保护根（字面或规范拼写）即抛 [FsError]。
  void _denyIfProtected(FsTarget target) {
    final List<String> written = <String>[
      _normalize(target.displayPath),
      _normalize(inner.processPath(target)),
    ];
    for (final String root in protectedRoots) {
      final Iterable<String> forms = <String>[root, ..._canonicalForms(root)];
      for (final String form in forms) {
        if (written.any((String path) => _under(path, form))) {
          throw const FsError(
            FsErrorCode.permissionDenied,
            kReadOnlyPathMessage,
          );
        }
      }
    }
  }
}

/// 受保护根的规范拼写；根尚不存在时为空（字面拼写仍然生效）。
Iterable<String> _canonicalForms(String root) sync* {
  try {
    yield _normalize(Directory(root).resolveSymbolicLinksSync());
  } on FileSystemException {
    return;
  }
}

/// 段级「相同或子孙」判定：`.opencode-backup` 不算 `.opencode`。
bool _under(String path, String root) {
  if (path.isEmpty || root.isEmpty) return false;
  if (path == root) return true;
  final String prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  return path.startsWith(prefix);
}

/// 去掉冗余的 `.` / `..` 与末尾分隔符（不解析符号链接）。
String _normalize(String path) {
  final RegExp separators = RegExp(r'[/\\]');
  final bool absolute =
      path.startsWith('/') || RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path);
  final List<String> parts = <String>[];
  for (final String part in path.split(separators)) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..' && parts.isNotEmpty && parts.last != '..') {
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  final String joined = parts.join(Platform.pathSeparator);
  return absolute ? '${Platform.pathSeparator}$joined' : joined;
}

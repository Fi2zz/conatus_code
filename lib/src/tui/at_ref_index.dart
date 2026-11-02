/// `@` 补全的递归索引：一次扫描工作区，跳过隐藏与可再生目录。
library;

import 'dart:io';

import 'package:conatus_fs_tools/conatus_fs_tools.dart';

/// 一个补全候选。
class AtRefCandidate {
  const AtRefCandidate({required this.path, required this.isDir});

  /// 相对 cwd 的补全路径；目录以 `/` 结尾。
  final String path;

  /// 是否目录（补全后继续列举子项）。
  final bool isDir;

  /// 列表展示的名字（末段，目录不带尾 `/`）。
  String get name {
    final String trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final int slash = trimmed.lastIndexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }
}

/// 惰性递归索引；同一菜单会话内复用，关闭时 [clear]。
class AtRefIndex {
  AtRefIndex(this.cwd);

  /// 每次扫描时提供基准目录。
  final String Function() cwd;

  List<AtRefCandidate>? _cache;

  /// 全部候选（目录带尾 `/`）。
  List<AtRefCandidate> all() => _cache ??= _walk();

  /// 丢弃缓存；文件系统变化后重新扫描。
  void clear() => _cache = null;

  List<AtRefCandidate> _walk() {
    final Directory root = Directory(cwd());
    if (!root.existsSync()) return const <AtRefCandidate>[];
    final List<AtRefCandidate> found = <AtRefCandidate>[];
    void visit(Directory dir, String prefix) {
      final List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final FileSystemEntity entity in entries) {
        final String name = entity.path.split(Platform.pathSeparator).last;
        if (name.isEmpty || name.startsWith('.')) continue;
        if (entity is Directory) {
          if (kDefaultSkipDirs.contains(name)) continue;
          found.add(AtRefCandidate(path: '$prefix$name/', isDir: true));
          visit(entity, '$prefix$name/');
        } else if (entity is File) {
          found.add(AtRefCandidate(path: '$prefix$name', isDir: false));
        }
      }
    }

    visit(root, '');
    return found;
  }
}

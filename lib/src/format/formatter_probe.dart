/// 「编辑后格式化」探针：按项目标记 + 文件扩展名决定跑什么命令。
///
/// 与 lint 探针不同，格式化命令天然按文件工作，因此探针只声明扩展名与
/// 命令前缀，文件绝对路径由调用方追加。项目标记（pubspec / go.mod /
/// Cargo.toml / package.json / pyproject）决定该目录属于哪种生态，避免在
/// 非对应项目里误跑不存在的工具。
library;

import 'dart:io';

import 'formatter_path.dart';

/// 一条格式化探针。
class FormatterProbe {
  const FormatterProbe({
    required this.name,
    required this.extensions,
    required this.command,
  });

  /// 探针名（`dart` / `go` / `rust` / `prettier` / `ruff`）。
  final String name;

  /// 适用的文件扩展名（含点、小写）。
  final List<String> extensions;

  /// 命令前缀；调用方在末尾追加转义后的文件绝对路径。
  final List<String> command;
}

/// 项目标记 → 探针。按声明顺序取第一个命中项。
class _Marker {
  const _Marker({
    required this.name,
    required this.file,
    required this.extensions,
    required this.command,
    this.contains,
  });

  final String name;
  final String file;
  final List<String> extensions;
  final List<String> command;

  /// 标记文件内必须出现的文本；`null` 表示只看文件是否存在。
  final String? contains;

  /// 标记是否命中：文件存在，且声明了 [contains] 时内容包含它。
  bool matches(String workdir) {
    final File marker = File('$workdir${Platform.pathSeparator}$file');
    if (!marker.existsSync()) return false;
    final String? needle = contains;
    if (needle == null) return true;
    try {
      return marker.readAsStringSync().contains(needle);
    } on FileSystemException {
      return false;
    }
  }
}

// REASON: 静态映射表（项目标记 → 命令），新增生态只加一行，探测优先级
// 也一眼可见。
const List<_Marker> _kMarkers = <_Marker>[
  _Marker(
    name: 'dart',
    file: 'pubspec.yaml',
    extensions: <String>['.dart'],
    command: <String>['dart', 'format'],
  ),
  _Marker(
    name: 'go',
    file: 'go.mod',
    extensions: <String>['.go'],
    command: <String>['gofmt', '-w'],
  ),
  _Marker(
    name: 'rust',
    file: 'Cargo.toml',
    extensions: <String>['.rs'],
    command: <String>['rustfmt'],
  ),
  _Marker(
    name: 'prettier',
    file: 'package.json',
    contains: 'prettier',
    extensions: <String>[
      '.js',
      '.jsx',
      '.ts',
      '.tsx',
      '.json',
      '.css',
      '.scss',
      '.less',
      '.md',
      '.yaml',
      '.yml',
      '.html',
    ],
    command: <String>['prettier', '--write'],
  ),
  _Marker(
    name: 'ruff',
    file: 'pyproject.toml',
    contains: '[tool.ruff',
    extensions: <String>['.py', '.pyi'],
    command: <String>['ruff', 'format'],
  ),
  _Marker(
    name: 'ruff',
    file: 'ruff.toml',
    extensions: <String>['.py', '.pyi'],
    command: <String>['ruff', 'format'],
  ),
];

/// 按项目标记探测 [path] 的格式化探针；认不出返回 `null`。
///
/// [path] 可以是相对工作目录的路径；越界与 `.opencode/**` 一律不探测。
FormatterProbe? detectFormatter(String workdir, String path) {
  final String? target = resolveFormatterTarget(workdir, path);
  if (target == null) return null;
  final String extension = formatterExtension(target);
  if (extension.isEmpty) return null;
  for (final _Marker marker in _kMarkers) {
    if (!marker.extensions.contains(extension)) continue;
    if (!marker.matches(workdir)) continue;
    return FormatterProbe(
      name: marker.name,
      extensions: marker.extensions,
      command: marker.command,
    );
  }
  return null;
}

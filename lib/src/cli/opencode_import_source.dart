/// OpenCode 配置源发现：全局、项目祖先、`.opencode` 与 `.json` / `.jsonc`。
///
/// 只读；顺序与 OpenCode 一致：全局 → 项目直接配置（远到近）→ `.opencode`
/// 配置（远到近）。同一目录同时存在 `.json` 与 `.jsonc` 时都读，`.jsonc` 排后。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'jsonc.dart';

/// 一份已解析的 OpenCode 配置。
class OpenCodeDocument {
  const OpenCodeDocument({required this.path, required this.values});

  /// 文件路径。
  final String path;

  /// 顶层对象。
  final Map<String, Object?> values;
}

/// 发现结果：[documents] 按优先级从低到高排列。
class OpenCodeSources {
  const OpenCodeSources({required this.documents, required this.warnings});

  final List<OpenCodeDocument> documents;
  final List<String> warnings;

  bool get isEmpty => documents.isEmpty;
}

/// 读取 [workdir] 可见的 OpenCode 配置。
///
/// [homeDir] / [env] 供测试注入；`XDG_CONFIG_HOME` 优先于 `~/.config`。
OpenCodeSources loadOpenCodeSources({
  required String workdir,
  bool includeGlobal = true,
  bool includeProject = true,
  String? homeDir,
  Map<String, String>? env,
}) {
  final List<String> warnings = <String>[];
  final List<String> files = <String>[
    if (includeGlobal)
      ..._jsonFiles(_globalConfigDir(homeDir, env), warnings),
    if (includeProject) ..._projectFiles(workdir, warnings),
  ];
  final List<OpenCodeDocument> documents = <OpenCodeDocument>[];
  for (final String path in files) {
    final OpenCodeDocument? document = _load(path, warnings);
    if (document != null) documents.add(document);
  }
  return OpenCodeSources(documents: documents, warnings: warnings);
}

String _globalConfigDir(String? homeDir, Map<String, String>? env) {
  final Map<String, String> source = env ?? Platform.environment;
  final String? xdg = source['XDG_CONFIG_HOME']?.trim();
  if (xdg != null && xdg.isNotEmpty) return _path(xdg, 'opencode');
  final String home = homeDir ?? resolveHomeDir();
  return _path(home, '.config/opencode');
}

List<String> _projectFiles(String workdir, List<String> warnings) {
  final List<String> ancestors = _ancestors(workdir);
  return <String>[
    for (final String dir in ancestors) ..._jsonFiles(dir, warnings),
    for (final String dir in ancestors)
      ..._jsonFiles(_path(dir, '.opencode'), warnings, warnBoth: false),
  ];
}

/// 最近的祖先在后，保证低优先级在前。
List<String> _ancestors(String workdir) {
  final List<String> dirs = <String>[];
  String current = Directory(workdir).absolute.path;
  while (true) {
    dirs.add(current);
    final String parent = Directory(current).parent.path;
    if (parent == current) return dirs.reversed.toList();
    current = parent;
  }
}

List<String> _jsonFiles(
  String dir,
  List<String> warnings, {
  bool warnBoth = true,
}) {
  final List<String> found = <String>[
    for (final String name in <String>['opencode.json', 'opencode.jsonc'])
      if (File(_path(dir, name)).existsSync()) _path(dir, name),
  ];
  if (warnBoth && found.length > 1) {
    warnings.add('${found.first} 与 ${found.last} 同时存在，按后者覆盖；建议只保留一个。');
  }
  return found;
}

OpenCodeDocument? _load(String path, List<String> warnings) {
  try {
    final Object? decoded = decodeJsonc(File(path).readAsStringSync());
    if (decoded is! Map) {
      warnings.add('$path 顶层不是对象，已跳过。');
      return null;
    }
    return OpenCodeDocument(
      path: path,
      values: Map<String, Object?>.from(decoded),
    );
  } on FormatException catch (error) {
    warnings.add('$path 解析失败：${error.message}');
  } on FileSystemException catch (error) {
    warnings.add('$path 读取失败：${error.message}');
  }
  return null;
}

String _path(String base, String relative) =>
    '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';

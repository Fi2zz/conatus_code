/// 项目插件发现：`.opencode/plugins/` 与 `opencode.json(c)` 的 `plugins`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../cli/jsonc.dart';
import 'plugin_config.dart';
import 'plugin_entry.dart';
import 'plugin_types.dart';

/// 发现结果。
class PluginDiscoveryResult {
  const PluginDiscoveryResult({
    this.candidates = const <PluginCandidate>[],
    this.warnings = const <String>[],
  });

  final List<PluginCandidate> candidates;
  final List<String> warnings;
}

/// 按 OpenCode 的项目约定发现插件。
class PluginDiscovery {
  PluginDiscovery({required this.workdir});

  /// 项目根（nava 的 workdir）。
  final String workdir;

  /// 扫描项目插件目录与 `opencode.json(c)`。
  Future<PluginDiscoveryResult> discoverProject() async {
    final List<String> warnings = <String>[];
    final Map<String, PluginCandidate> found = <String, PluginCandidate>{};
    _scanPluginDir(Directory('$workdir/.opencode/plugins'), found, warnings);
    for (final File file in _configFiles()) {
      _scanConfigFile(file, found, warnings);
    }
    return PluginDiscoveryResult(
      candidates: found.values.toList(growable: false),
      warnings: warnings,
    );
  }

  List<File> _configFiles() => <File>[
    for (final String name in <String>['opencode.json', 'opencode.jsonc']) ...[
      File('$workdir/$name'),
      File('$workdir/.opencode/$name'),
    ],
  ].where((File file) => file.existsSync()).toList(growable: false);

  void _scanPluginDir(
    Directory dir,
    Map<String, PluginCandidate> found,
    List<String> warnings,
  ) {
    if (!dir.existsSync()) return;
    final List<FileSystemEntity> entries = dir.listSync()
      ..sort(
        (FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path),
      );
    for (final FileSystemEntity entity in entries) {
      if (entity is File) {
        final String ext = _extension(entity.path);
        if (ext == '.js' || ext == '.mjs' || ext == '.cjs') {
          _addLocal(entity.path, 'project-plugins', found, warnings);
        } else if (ext == '.ts') {
          warnings.add('忽略 TypeScript 插件 ${entity.path}（P4.1 只支持 JS）。');
        }
        continue;
      }
      if (entity is Directory) {
        final String? entry = directoryPluginEntry(entity.path);
        if (entry == null) {
          warnings.add('插件目录缺少入口：${entity.path}');
          continue;
        }
        _addLocal(entry, 'project-plugins', found, warnings);
      }
    }
  }

  void _scanConfigFile(
    File file,
    Map<String, PluginCandidate> found,
    List<String> warnings,
  ) {
    final Object? decoded;
    try {
      decoded = decodeJsonc(file.readAsStringSync());
    } on FormatException catch (error) {
      warnings.add('读取 ${file.path} 失败：${error.message}');
      return;
    }
    if (decoded is! Map) return;
    final Object? plugins = decoded['plugins'];
    if (plugins is! List) return;
    for (final Object? item in plugins) {
      final String? source;
      final Map<String, Object?> options;
      if (item is String) {
        source = item;
        options = const <String, Object?>{};
      } else if (item is Map && item['package'] is String) {
        source = item['package'] as String;
        final Object? rawOptions = item['options'];
        options = rawOptions is Map
            ? rawOptions.cast<String, Object?>()
            : const <String, Object?>{};
      } else {
        warnings.add('${file.path} 的 plugins 项不是字符串或 {package} 表，已跳过。');
        continue;
      }
      if (source.trim().isEmpty) continue;
      if (isLocalPluginSource(source)) {
        final String path = resolveLocalPluginSource(
          source,
          base: file.parent.path,
        );
        _addLocal(
          directoryPluginEntry(path) ?? path,
          'project-config',
          found,
          warnings,
          options: options,
        );
      } else {
        _addPackage(source, 'project-config', found, options: options);
      }
    }
  }

  void _addLocal(
    String path,
    String origin,
    Map<String, PluginCandidate> found,
    List<String> warnings, {
    Map<String, Object?> options = const <String, Object?>{},
  }) {
    final File entry = File(path);
    if (!entry.existsSync()) {
      warnings.add('插件入口不存在：$path');
      return;
    }
    final String canonical = entry.absolute.path;
    final String id = pluginIdFor(canonical);
    found.putIfAbsent(
      canonical,
      () => PluginCandidate(
        spec: PluginSpec(
          id: id,
          source: canonical,
          options: options,
          projectScoped: true,
        ),
        origin: origin,
        entry: canonical,
        fingerprint: _localFingerprint(entry),
      ),
    );
  }

  void _addPackage(
    String source,
    String origin,
    Map<String, PluginCandidate> found, {
    Map<String, Object?> options = const <String, Object?>{},
  }) {
    found.putIfAbsent(
      source,
      () => PluginCandidate(
        spec: PluginSpec(
          id: pluginIdFor(source),
          source: source,
          options: options,
          projectScoped: true,
        ),
        origin: origin,
        entry: source,
        fingerprint: source,
        local: false,
      ),
    );
  }

  String _localFingerprint(File entry) {
    final StringBuffer buffer = StringBuffer()..write(entry.readAsStringSync());
    final File packageFile = File('${entry.parent.path}/package.json');
    if (packageFile.existsSync()) buffer.write(packageFile.readAsStringSync());
    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }

  String _extension(String path) {
    final int slash = path.lastIndexOf(Platform.pathSeparator);
    final int dot = path.lastIndexOf('.');
    return dot > slash ? path.substring(dot) : '';
  }
}

/// 本地插件入口解析与候选构造。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'plugin_types.dart';

/// 构造一个本地插件候选（配置项也走同一指纹规则）。
///
/// [path] 可以是文件或目录；目录按 package.json main / index.js 解析入口。
PluginCandidate localPluginCandidate(
  String path, {
  String origin = 'config',
  Map<String, Object?> options = const <String, Object?>{},
  bool projectScoped = false,
}) {
  final String? entryPath = pluginEntryOf(path);
  if (entryPath == null) {
    throw FileSystemException('插件目录缺少入口', path);
  }
  final File entry = File(entryPath).absolute;
  final String canonical = entry.path;
  final StringBuffer buffer = StringBuffer()..write(entry.readAsStringSync());
  final File packageFile = File('${entry.parent.path}/package.json');
  if (packageFile.existsSync()) buffer.write(packageFile.readAsStringSync());
  return PluginCandidate(
    spec: PluginSpec(
      id: pluginIdFor(canonical),
      source: canonical,
      options: options,
      projectScoped: projectScoped,
    ),
    origin: origin,
    entry: canonical,
    fingerprint: sha256.convert(utf8.encode(buffer.toString())).toString(),
  );
}

/// 解析本地路径到插件入口：文件原样返回；目录找 main / index。
String? pluginEntryOf(String path) {
  final FileSystemEntityType type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.file) return File(path).absolute.path;
  if (type != FileSystemEntityType.directory) return null;
  return directoryPluginEntry(path);
}

/// 目录入口：`package.json` 的 `main`，否则 `index.js` / `index.mjs` / `index.cjs`。
String? directoryPluginEntry(String dir) {
  final File packageFile = File('$dir/package.json');
  if (packageFile.existsSync()) {
    try {
      final Object? decoded = jsonDecode(packageFile.readAsStringSync());
      if (decoded is Map) {
        final Object? main = decoded['main'];
        if (main is String && main.isNotEmpty) {
          final File target = File('$dir/$main');
          if (target.existsSync()) return target.absolute.path;
        }
      }
    } on FormatException {
      // 落到默认入口。
    }
  }
  for (final String name in <String>['index.js', 'index.mjs', 'index.cjs']) {
    final File target = File('$dir/$name');
    if (target.existsSync()) return target.absolute.path;
  }
  return null;
}

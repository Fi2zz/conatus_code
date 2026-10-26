/// OpenCode `references` JSON → nava `[references.*]`（仅本地目录）。
library;

import 'dart:io';

import 'opencode_import_fields.dart';
import 'opencode_import_types.dart';

/// 映射 `references` 对象；git reference 告警跳过。
List<ImportedReference> mapOpenCodeReferences(
  Object? raw,
  String source,
  String baseDir,
  List<String> warnings,
) {
  if (raw == null) return const <ImportedReference>[];
  if (raw is! Map) {
    warnings.add('$source: references 必须是对象，已忽略。');
    return const <ImportedReference>[];
  }
  final List<ImportedReference> result = <ImportedReference>[];
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    final ImportedReference? reference = _reference(
      entry.key.toString().trim(),
      entry.value,
      source,
      baseDir,
      warnings,
    );
    if (reference != null) result.add(reference);
  }
  return result;
}

ImportedReference? _reference(
  String name,
  Object? raw,
  String source,
  String baseDir,
  List<String> warnings,
) {
  if (name.isEmpty) {
    warnings.add('$source: references 有空别名，已跳过。');
    return null;
  }
  if (raw is String) {
    if (!_localPath(raw)) {
      warnings.add('$source: references.$name 是 git 引用，暂不支持，已跳过。');
      return null;
    }
    return ImportedReference(
      name: name,
      path: _resolve(raw, baseDir),
    );
  }
  if (raw is! Map) {
    warnings.add('$source: references.$name 必须是字符串或对象，已跳过。');
    return null;
  }
  if (raw['repository'] != null && raw['path'] == null) {
    warnings.add('$source: references.$name 是 git 引用，暂不支持，已跳过。');
    return null;
  }
  final String? path = openCodeString(raw['path']);
  if (path == null) {
    warnings.add('$source: references.$name 缺少 path，已跳过。');
    return null;
  }
  return ImportedReference(
    name: name,
    path: _resolve(path, baseDir),
    description: openCodeString(raw['description']) ?? '',
  );
}

/// 以 `.` / `/` / `~` 开头才是本地路径；裸字符串在 OpenCode 里是 git 仓库。
bool _localPath(String raw) {
  final String value = raw.trim();
  return value.startsWith('.') || value.startsWith('/') || value.startsWith('~');
}

String _resolve(String raw, String baseDir) {
  final String value = raw.trim();
  if (value.startsWith('~')) return value;
  if (value.startsWith('/')) return value;
  String relative = value;
  while (relative.startsWith('./')) {
    relative = relative.substring(2);
  }
  final String joined = '$baseDir${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}';
  return Uri.file(joined).normalizePath().toFilePath();
}

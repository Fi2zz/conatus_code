/// `config.toml` 的写入：追加 provider 段与设置 `default_model`。
///
/// 纯文本操作，只改动目标行/段，保留文件其余内容与注释（不重写整份文件）。
library;

import 'dart:io';

/// 追加 `[providers.<name>]` 段，返回新内容。
///
/// 名字只含 TOML 裸键字符（`A-Za-z0-9_-`）时用裸键，否则加双引号
/// （如 `managed:kimi-code` → `[providers."managed:kimi-code"]`）。
String appendProviderSection(
  String toml, {
  required String name,
  required String baseUrl,
  required String apiKey,
  required String type,
}) {
  final StringBuffer buffer = StringBuffer(toml);
  if (toml.isNotEmpty && !toml.endsWith('\n')) {
    buffer.write('\n');
  }
  buffer
    ..write('\n[providers.')
    ..write(_tomlKey(name))
    ..write(']\n');
  if (apiKey.isNotEmpty) {
    buffer.write('api_key = "${_tomlString(apiKey)}"\n');
  }
  buffer
    ..write('base_url = "${_tomlString(baseUrl)}"\n')
    ..write('type = "$type"\n');
  return buffer.toString();
}

/// 设置 `[llm]` 段的 `default_model = "<value>"`，返回新内容。
///
/// 段内已有**非注释**的 `default_model` 行则替换它；只有注释行则在 `[llm]`
/// 段首行后插入一行；整份文件没有 `[llm]` 段则追加该段。
String upsertDefaultModel(String toml, String value) {
  final List<String> lines = toml.split('\n');
  final int sectionStart = lines.indexWhere(_isLlmSection);
  if (sectionStart < 0) {
    final StringBuffer buffer = StringBuffer(toml);
    if (toml.isNotEmpty && !toml.endsWith('\n')) {
      buffer.write('\n');
    }
    buffer.write('\n[llm]\ndefault_model = "${_tomlString(value)}"\n');
    return buffer.toString();
  }
  final int sectionEnd = _sectionEnd(lines, sectionStart);
  final int existing = _defaultModelLine(lines, sectionStart, sectionEnd);
  final String assignment = 'default_model = "${_tomlString(value)}"';
  if (existing >= 0) {
    lines[existing] = assignment;
  } else {
    lines.insert(sectionStart + 1, assignment);
  }
  return lines.join('\n');
}

/// 写入文件（父目录自动创建）。
void writeConfigFile(String path, String content) {
  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

/// 读 [path] → 追加 provider 段（[defaultModel] 非空时一并设置）→ 写回。
///
/// 文件不存在时按空内容起头（等价于新建）。
void appendProviderToFile(
  String path, {
  required String name,
  required String baseUrl,
  required String apiKey,
  required String type,
  String? defaultModel,
}) {
  final File file = File(path);
  String toml = file.existsSync() ? file.readAsStringSync() : '';
  toml = appendProviderSection(
    toml,
    name: name,
    baseUrl: baseUrl,
    apiKey: apiKey,
    type: type,
  );
  if (defaultModel != null) {
    toml = upsertDefaultModel(toml, defaultModel);
  }
  writeConfigFile(path, toml);
}

bool _isLlmSection(String line) => line.trim() == '[llm]';

/// `[llm]` 段结束下标（下一个表头或文件末尾）。
int _sectionEnd(List<String> lines, int start) {
  for (int index = start + 1; index < lines.length; index++) {
    final String trimmed = lines[index].trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) return index;
  }
  return lines.length;
}

/// 段内非注释的 `default_model` 行下标；没有返回 `-1`。
int _defaultModelLine(List<String> lines, int start, int end) {
  for (int index = start + 1; index < end; index++) {
    final String trimmed = lines[index].trim();
    if (!trimmed.startsWith('#') && trimmed.startsWith('default_model')) {
      return index;
    }
  }
  return -1;
}

/// TOML 键：裸键字符集之外加双引号。
String _tomlKey(String name) {
  final bool bare = RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name);
  return bare ? name : '"${_tomlString(name)}"';
}

/// TOML 基本字符串转义（`\` 与 `"`）。
String _tomlString(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

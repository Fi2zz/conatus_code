/// TOML 片段拼接共用的键名与字符串转义。
library;

/// TOML 键：裸键字符集之外加双引号。
///
/// `ark` → `ark`；`managed:kimi-code` → `"managed:kimi-code"`。
String tomlKey(String name) {
  final bool bare = RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name);
  return bare ? name : '"${tomlString(name)}"';
}

/// TOML 基本字符串转义（`\` 与 `"`）。
String tomlString(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

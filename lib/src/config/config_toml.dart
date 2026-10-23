/// TOML 片段拼接共用的键名与字符串转义。
library;

/// TOML 键：裸键字符集之外加双引号。
///
/// `ark` → `ark`；`managed:kimi-code` → `"managed:kimi-code"`。
String tomlKey(String name) {
  final bool bare = RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name);
  return bare ? name : '"${tomlString(name)}"';
}

/// TOML 基本字符串转义：`\` `"` 与全部控制字符，保证写入后仍是单行合法字符串。
String tomlString(String value) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in value.runes) {
    final String? escaped = _tomlEscapes[rune];
    if (escaped != null) {
      buffer.write(escaped);
    } else if (rune < 0x20 || rune == 0x7F) {
      buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
    } else {
      buffer.write(String.fromCharCode(rune));
    }
  }
  return buffer.toString();
}

const Map<int, String> _tomlEscapes = <int, String>{
  0x08: r'\b',
  0x09: r'\t',
  0x0A: r'\n',
  0x0C: r'\f',
  0x0D: r'\r',
  0x22: r'\"',
  0x5C: r'\\',
};

/// `config.toml` 的插件块删除：只改匹配块，保留注释与其余配置。
library;

/// 从 TOML 文本里删掉 `source = "<source>"` 的 `[[plugins]]` 块。
String removePluginBlock(String toml, String source) {
  final List<String> lines = toml.split('\n');
  final List<String> kept = <String>[];
  bool matched = false;
  int index = 0;
  while (index < lines.length) {
    if (lines[index].trim() != '[[plugins]]') {
      kept.add(lines[index]);
      index++;
      continue;
    }
    final List<String> block = <String>[lines[index]];
    index++;
    while (index < lines.length && !lines[index].trim().startsWith('[')) {
      block.add(lines[index]);
      index++;
    }
    final bool hit = block.any((String line) {
      final String trimmed = line.trim();
      if (!trimmed.startsWith('source = ')) return false;
      final String value = trimmed
          .substring('source = '.length)
          .replaceAll('"', '')
          .replaceAll("'", '')
          .trim();
      return value == source.trim();
    });
    if (hit) {
      matched = true;
      if (kept.isNotEmpty && kept.last.trim().isEmpty) kept.removeLast();
    } else {
      kept.addAll(block);
    }
  }
  if (!matched) return toml;
  return kept.join('\n');
}

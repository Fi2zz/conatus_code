/// 从补丁文本里抽取目标文件（unified diff 与 OpenCode `***` 两种格式）。
///
/// 只做「够用」的解析：安全护栏需要知道哪些已有文件会被改动、哪些是新建。
/// 解析不到路径时返回空列表，调用方按 fail-open 处理。
library;

/// 一个补丁目标。
class PatchTarget {
  const PatchTarget({required this.path, this.creates = false});

  /// 工作区相对或绝对路径（已去掉 `a/` / `b/` 前缀）。
  final String path;

  /// 是否新建文件（新建豁免读后写检查）。
  final bool creates;
}

/// 抽取补丁涉及的文件；同一路径出现多次时 `creates=false` 优先。
List<PatchTarget> patchTargets(String patch) {
  final Map<String, bool> found = <String, bool>{};
  String? pendingOld;
  for (final String rawLine in patch.split('\n')) {
    final String line = rawLine.trimRight();
    if (line.startsWith('*** ')) {
      pendingOld = _openCodeLine(found, line.substring(4));
      continue;
    }
    if (line.startsWith('--- ')) {
      pendingOld = _cleanPath(line.substring(4));
      continue;
    }
    if (line.startsWith('+++ ')) {
      _unifiedPlus(found, _cleanPath(line.substring(4)), pendingOld);
      pendingOld = null;
    }
  }
  return <PatchTarget>[
    for (final MapEntry<String, bool> entry in found.entries)
      PatchTarget(path: entry.key, creates: entry.value),
  ];
}

/// OpenCode 标记行；返回该行同时充当的 `---` 旧路径（仅 Update/Delete）。
String? _openCodeLine(Map<String, bool> found, String rest) {
  if (rest.startsWith('Add File: ')) {
    _add(found, rest.substring(10), creates: true);
    return null;
  }
  if (rest.startsWith('Update File: ')) {
    final String path = _cleanPath(rest.substring(13));
    _add(found, path, creates: false);
    return path;
  }
  if (rest.startsWith('Delete File: ')) {
    final String path = _cleanPath(rest.substring(13));
    _add(found, path, creates: false);
    return path;
  }
  return null;
}

void _unifiedPlus(Map<String, bool> found, String plus, String? pendingOld) {
  if (plus == '/dev/null') {
    if (pendingOld != null) _add(found, pendingOld, creates: false);
    return;
  }
  _add(found, plus, creates: pendingOld == '/dev/null');
}

void _add(Map<String, bool> found, String raw, {required bool creates}) {
  final String path = _cleanPath(raw);
  if (path.isEmpty || path == '/dev/null') return;
  final bool? existing = found[path];
  found[path] = existing == false ? false : creates;
}

String _cleanPath(String raw) {
  String path = raw.split('\t').first.trim();
  if (path.length >= 2) {
    final bool quoted =
        (path.startsWith('"') && path.endsWith('"')) ||
        (path.startsWith("'") && path.endsWith("'"));
    if (quoted) path = path.substring(1, path.length - 1);
  }
  if (path.startsWith('a/') || path.startsWith('b/')) {
    path = path.substring(2);
  }
  return path;
}

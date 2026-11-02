/// `@` 补全的匹配与排序：子串优先，子序列兜底。
library;

import 'at_ref_index.dart';

/// 候选是否匹配查询（大小写不敏感）。
bool atRefMatches(String query, AtRefCandidate candidate) {
  final String q = query.toLowerCase();
  final String path = candidate.path.toLowerCase();
  final String base = candidate.name.toLowerCase();
  if (base.contains(q) || path.contains(q)) return true;
  return _fuzzy(q, base);
}

/// 排序：目录优先；同层按 basename 前缀 → 路径前缀 → basename 包含 →
/// 路径包含 → 子序列；再按路径长度与字典序稳定收口。
void sortAtRefCandidates(List<AtRefCandidate> found, String query) {
  final String q = query.toLowerCase();
  found.sort((AtRefCandidate a, AtRefCandidate b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    if (q.isEmpty) return a.name.compareTo(b.name);
    final int byScore = _score(a, q).compareTo(_score(b, q));
    if (byScore != 0) return byScore;
    final int byLength = a.path.length.compareTo(b.path.length);
    return byLength != 0 ? byLength : a.path.compareTo(b.path);
  });
}

int _score(AtRefCandidate candidate, String query) {
  if (query.isEmpty) return 0;
  final String path = candidate.path.toLowerCase();
  final String base = candidate.name.toLowerCase();
  if (base.startsWith(query)) return 0;
  if (path.startsWith(query)) return 1;
  if (base.contains(query)) return 2;
  if (path.contains(query)) return 3;
  return 4;
}

/// 子序列匹配：`mn` 能命中 `main.dart`。
bool _fuzzy(String query, String target) {
  int index = 0;
  for (int i = 0; i < target.length && index < query.length; i++) {
    if (target[i] == query[index]) index++;
  }
  return index == query.length;
}

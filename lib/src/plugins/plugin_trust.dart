/// 项目插件信任：首次审批、内容指纹与持久化。
library;

import 'dart:convert';
import 'dart:io';

import 'plugin_types.dart';

/// 一次审批的结论。
enum PluginTrustDecision { allowOnce, allowAlways, deny }

/// 审批回调；传入未信任的候选，返回结论。
typedef PluginTrustPrompter =
    Future<PluginTrustDecision> Function(List<PluginCandidate> candidates);

/// 交互式首次审批：在 TUI 启动前用一行 stdin 询问。
///
/// 非终端（管道 / CI）直接拒绝，避免脚本里静默执行项目插件。
Future<PluginTrustDecision> stdinPluginTrustPrompter(
  List<PluginCandidate> candidates, {
  StringSink? err,
  Stdin? input,
}) async {
  final StringSink sink = err ?? stderr;
  final Stdin source = input ?? stdin;
  if (!source.hasTerminal) return PluginTrustDecision.deny;
  sink.writeln('项目要求加载 ${candidates.length} 个插件（插件是任意代码）：');
  for (final PluginCandidate candidate in candidates) {
    sink.writeln('  - ${candidate.spec.source}  [${candidate.origin}]');
  }
  sink.write('允许？[a]lways / [o]nce / [d]eny：');
  final String answer = (source.readLineSync() ?? '').trim().toLowerCase();
  sink.writeln();
  return switch (answer) {
    'a' || 'always' || 'y' || 'yes' => PluginTrustDecision.allowAlways,
    'o' || 'once' => PluginTrustDecision.allowOnce,
    _ => PluginTrustDecision.deny,
  };
}

/// 信任记录；文件格式 `{ "entries": { "<id>": "<fingerprint>" } }`。
class PluginTrustStore {
  PluginTrustStore({
    required this.path,
    this.prompter,
    this.autoTrust = false,
    this.autoDeny = false,
  });

  /// 记录文件路径（`$baseDir/plugin-trust.json`）。
  final String path;

  /// 首次审批回调；`null` 时未信任项一律拒绝。
  final PluginTrustPrompter? prompter;

  /// 直接信任（`--trust-plugins`）。
  final bool autoTrust;

  /// 直接拒绝（headless 缺省）。
  final bool autoDeny;

  final Map<String, String> _entries = <String, String>{};
  bool _loaded = false;

  /// 读取并筛选候选；只返回已信任或本次批准的项。
  Future<List<PluginCandidate>> filter(List<PluginCandidate> candidates) async {
    if (candidates.isEmpty) return const <PluginCandidate>[];
    if (autoTrust) return candidates;
    if (autoDeny) return const <PluginCandidate>[];
    _load();
    final List<PluginCandidate> trusted = <PluginCandidate>[];
    final List<PluginCandidate> unresolved = <PluginCandidate>[];
    for (final PluginCandidate candidate in candidates) {
      if (_entries[candidate.spec.id] == candidate.fingerprint) {
        trusted.add(candidate);
      } else {
        unresolved.add(candidate);
      }
    }
    if (unresolved.isEmpty) return trusted;
    final PluginTrustPrompter? ask = prompter;
    if (ask == null) return trusted;
    final PluginTrustDecision decision = await ask(unresolved);
    if (decision == PluginTrustDecision.deny) return trusted;
    if (decision == PluginTrustDecision.allowAlways) {
      for (final PluginCandidate candidate in unresolved) {
        _entries[candidate.spec.id] = candidate.fingerprint;
      }
      await save();
    }
    return <PluginCandidate>[...trusted, ...unresolved];
  }

  /// 写入信任记录（原子写 + 0600）。
  Future<void> save() async {
    if (path.isEmpty) return;
    final Directory dir = File(path).parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final File temp = File('$path.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(<String, Object?>{'entries': _entries}),
      flush: true,
    );
    await temp.rename(path);
    await _chmod600(path);
  }

  void _load() {
    if (_loaded) return;
    _loaded = true;
    final File file = File(path);
    if (!file.existsSync()) return;
    try {
      final Object? decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return;
      final Object? entries = decoded['entries'];
      if (entries is! Map) return;
      for (final MapEntry<Object?, Object?> entry in entries.entries) {
        _entries['${entry.key}'] = '${entry.value}';
      }
    } on FormatException {
      _entries.clear();
    }
  }

  Future<void> _chmod600(String file) async {
    try {
      await Process.run('chmod', <String>['600', file]);
    } on ProcessException {
      // 非 POSIX 平台忽略；内容本身不含秘密。
    }
  }
}

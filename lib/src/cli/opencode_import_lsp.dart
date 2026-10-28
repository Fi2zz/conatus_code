/// OpenCode `lsp` → nava `[lsp]`。
library;

import 'dart:io';

import '../config/config_schema.dart';

/// 映射 OpenCode lsp；无该字段返回 null。
LspConfig? mapOpenCodeLsp(
  Object? raw,
  String source,
  String workdir,
  List<String> warnings,
) {
  if (raw == null) return null;
  if (raw == false) return const LspConfig();
  if (raw == true) {
    if (!File('$workdir${Platform.pathSeparator}pubspec.yaml').existsSync()) {
      warnings.add(
        '$source: lsp=true 需要内置服务器，nava 当前仅支持 Dart（未发现 pubspec.yaml），已跳过。',
      );
      return const LspConfig();
    }
    return const LspConfig(
      enabled: true,
      servers: <LspServerConfig>[
        LspServerConfig(
          name: 'dart',
          command: <String>['dart', 'language-server'],
          extensions: <String>['.dart'],
        ),
      ],
    );
  }
  if (raw is! Map) {
    warnings.add('$source: lsp 必须是 true/false/对象，已忽略。');
    return const LspConfig();
  }
  final List<LspServerConfig> servers = <LspServerConfig>[];
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    final String name = entry.key.toString().trim();
    final Object? value = entry.value;
    if (value is! Map) {
      warnings.add('$source: lsp.$name 必须是对象，已忽略。');
      continue;
    }
    final Map<String, dynamic> server = value.cast<String, dynamic>();
    if (server['disabled'] == true) {
      warnings.add('$source: lsp.$name 已禁用，跳过。');
      continue;
    }
    final List<String> command = _strings(server['command']);
    if (command.isEmpty) {
      warnings.add('$source: lsp.$name 缺少 command，已跳过。');
      continue;
    }
    final List<String> extensions = <String>[
      for (final String item in _strings(server['extensions']))
        if (item.trim().isNotEmpty)
          item.trim().startsWith('.')
              ? item.trim().toLowerCase()
              : '.${item.trim().toLowerCase()}',
    ];
    final Map<String, String> env = <String, String>{};
    final Object? rawEnv = server['env'];
    if (rawEnv is Map) {
      for (final MapEntry<Object?, Object?> item in rawEnv.entries) {
        if (item.value is String) {
          env['${item.key}'] = item.value! as String;
        }
      }
    }
    final Map<String, Object?> initialization = <String, Object?>{};
    final Object? rawInit = server['initialization'];
    if (rawInit is Map) {
      initialization.addAll(rawInit.cast<String, Object?>());
    }
    servers.add(
      LspServerConfig(
        name: name,
        command: command,
        extensions: extensions,
        env: env,
        initialization: initialization,
      ),
    );
  }
  return LspConfig(enabled: true, servers: servers);
}

List<String> _strings(Object? raw) {
  if (raw is! List) return const <String>[];
  return <String>[
    for (final Object? item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

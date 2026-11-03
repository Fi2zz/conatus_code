/// `[[plugins]]` 的 Dart 侧视图：配置 → 候选、TOML 片段与路径判定。
library;

import 'dart:io';

import 'package:conatus_core/conatus_core.dart' show Context;

import '../config/config_schema.dart';
import 'plugin_types.dart';

/// 把配置声明转成插件规格。
PluginSpec pluginSpecFromConfig(PluginConfig config) => PluginSpec(
  id: pluginIdFor(config.source),
  source: config.source,
  options: config.options,
  enabled: config.enabled,
);

/// 配置里的全部启用插件。
List<PluginSpec> configuredPlugins(ConatusCodeConfig config) => <PluginSpec>[
  for (final PluginConfig entry in config.plugins)
    if (entry.enabled) pluginSpecFromConfig(entry),
];

/// 是否为本地路径（`.` / `/` / `~` 开头）。
bool isLocalPluginSource(String source) {
  final String value = source.trim();
  return value.startsWith('.') ||
      value.startsWith('/') ||
      value.startsWith('~');
}

/// 展开 `~` 并相对 [base] 解析本地路径。
String resolveLocalPluginSource(String source, {required String base}) {
  final String value = source.trim();
  final String expanded = value.startsWith('~')
      ? value.replaceFirst('~', Platform.environment['HOME'] ?? base)
      : value;
  return File(expanded).isAbsolute
      ? File(expanded).absolute.path
      : File('$base${Platform.pathSeparator}$expanded').absolute.path;
}

/// 生成写回 config.toml 的 `[[plugins]]` 片段。
String pluginTomlSnippet(
  String source, {
  Map<String, Object?> options = const <String, Object?>{},
}) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('[[plugins]]')
    ..writeln('source = ${_tomlString(source)}');
  if (options.isNotEmpty) {
    buffer.writeln('options = ${_tomlInlineTable(options)}');
  }
  return buffer.toString();
}

String _tomlString(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

String _tomlInlineTable(Map<String, Object?> value) {
  final List<String> parts = <String>[
    for (final MapEntry<String, Object?> entry in value.entries)
      '${_tomlKey(entry.key)} = ${_tomlValue(entry.value)}',
  ];
  return '{ ${parts.join(', ')} }';
}

String _tomlKey(String key) =>
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key) ? key : _tomlString(key);

String _tomlValue(Object? value) {
  if (value is String) return _tomlString(value);
  if (value is num || value is bool) return '$value';
  if (value is List) {
    return '[${value.map(_tomlValue).join(', ')}]';
  }
  if (value is Map) {
    return _tomlInlineTable(value.cast<String, Object?>());
  }
  return _tomlString('$value');
}

/// 从 npm/git spec 里取包名；无法判断返回 `null`。
String? packageNameOf(String source) {
  final String value = source.trim();
  if (value.startsWith('@')) {
    final int slash = value.indexOf('/');
    if (slash < 0) return null;
    final int at = value.indexOf('@', slash);
    return at < 0 ? value : value.substring(0, at);
  }
  if (value.startsWith('git') ||
      value.startsWith('github:') ||
      value.startsWith('http')) {
    return null;
  }
  final int at = value.indexOf('@');
  return at <= 0 ? value : value.substring(0, at);
}

/// 从 npm/git spec 里取可 `import()` 的包名。
///
/// `superpowers@git+https://...` → `superpowers`；`@scope/pkg@1.2` → `@scope/pkg`；
/// `github:me/repo` → `repo`（npm 安装后以 package.json name 为准，这一层只做
/// 常规推导）。
String packageImportName(String source) {
  final String value = source.trim();
  final String noSelector = value.split('::').first.split('#').first;
  final String? name = packageNameOf(noSelector);
  if (name != null) return name;
  final String last = noSelector.split(RegExp(r'[/\\]')).last;
  if (last.endsWith('.git')) {
    return last.substring(0, last.length - 4);
  }
  return last;
}

/// 从根 Context 取插件服务；未装配返回 `null`。
PluginServiceLike? pluginServiceOf(Context ctx) =>
    ctx.get<PluginServiceLike>(kPluginServiceKey);

/// 避免 plugins 模块反向依赖 service 的窄接口。
abstract class PluginServiceLike {
  /// 是否成功启动。
  bool get available;

  /// 插件注册的技能根。
  List<String> get skillRoots;

  /// 注入 system prompt 的上下文。
  String get contextText;

  /// 注入 shell 的环境变量。
  Map<String, String> get shellEnv;

  /// 已登记 / 待加载的插件数量（诊断用）。
  int get pluginCount => 0;

  /// 插件注册的工具数（诊断用）。
  int get toolCount => 0;

  /// 启动 / 加载阶段的告警（诊断用）。
  List<String> get warnings => const <String>[];

  /// 发送一个事件。
  Future<void> notify(String event, [Map<String, Object?> data = const {}]);
}

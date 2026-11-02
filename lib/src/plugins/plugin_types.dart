/// 插件宿主的数据模型：声明、候选、初始化结果与工具/技能描述。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 服务键。
const String kPluginServiceKey = 'plugins';

/// 一个插件的稳定标识：取 source 末段 + 内容哈希前 8 位。
String pluginIdFor(String source) {
  final String normalized = source.trim();
  final String last = normalized.split(RegExp(r'[/\\]')).last;
  final String base = last
      .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final String hash = sha256
      .convert(utf8.encode(normalized))
      .toString()
      .substring(0, 8);
  return '${base.isEmpty ? 'plugin' : base}-$hash';
}

/// 一个插件声明（配置或项目发现）。
class PluginSpec {
  const PluginSpec({
    required this.id,
    required this.source,
    this.options = const <String, Object?>{},
    this.enabled = true,
    this.projectScoped = false,
  });

  /// 稳定标识（信任记录键）。
  final String id;

  /// 本地目录或包 spec。
  final String source;

  /// 传给插件的 options。
  final Map<String, Object?> options;

  /// 是否启用。
  final bool enabled;

  /// 是否来自项目（需要首次审批）。
  final bool projectScoped;

  PluginSpec copyWith({bool? enabled, bool? projectScoped}) => PluginSpec(
    id: id,
    source: source,
    options: options,
    enabled: enabled ?? this.enabled,
    projectScoped: projectScoped ?? this.projectScoped,
  );
}

/// 发现阶段解析出的插件候选。
class PluginCandidate {
  const PluginCandidate({
    required this.spec,
    required this.origin,
    required this.entry,
    required this.fingerprint,
    this.local = true,
  });

  /// 声明。
  final PluginSpec spec;

  /// `config` / `project-plugins` / `project-config`。
  final String origin;

  /// 绝对路径（本地）或包 spec（npm/git）。
  final String entry;

  /// 内容指纹；变化后重新审批。
  final String fingerprint;

  /// 是否本地目录/文件。
  final bool local;

  Map<String, Object?> toInitJson() => <String, Object?>{
    'id': spec.id,
    'source': spec.source,
    'entry': entry,
    'options': spec.options,
    'local': local,
  };
}

/// 插件注册的技能。
class PluginSkill {
  const PluginSkill({
    required this.id,
    required this.name,
    this.description = '',
    this.path = '',
    this.content = '',
  });

  final String id;
  final String name;
  final String description;
  final String path;
  final String content;

  factory PluginSkill.fromJson(Map<String, Object?> json) => PluginSkill(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? json['id'] ?? ''}',
    description: '${json['description'] ?? ''}',
    path: '${json['path'] ?? ''}',
    content: '${json['content'] ?? ''}',
  );
}

/// 插件注册的自定义工具。
class PluginToolSpec {
  const PluginToolSpec({
    required this.name,
    required this.description,
    this.parameters = const <String, Object?>{},
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;

  factory PluginToolSpec.fromJson(Map<String, Object?> json) {
    final Object? params = json['parameters'];
    return PluginToolSpec(
      name: '${json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      parameters: params is Map
          ? params.cast<String, Object?>()
          : const <String, Object?>{},
    );
  }
}

/// 一次插件初始化的聚合结果。
class PluginInitResult {
  const PluginInitResult({
    this.skills = const <PluginSkill>[],
    this.skillRoots = const <String>[],
    this.tools = const <PluginToolSpec>[],
    this.context = '',
    this.shellEnv = const <String, String>{},
    this.warnings = const <String>[],
  });

  final List<PluginSkill> skills;
  final List<String> skillRoots;
  final List<PluginToolSpec> tools;
  final String context;
  final Map<String, String> shellEnv;
  final List<String> warnings;

  factory PluginInitResult.fromJson(Map<String, Object?> json) {
    final Object? skills = json['skills'];
    final Object? roots = json['skillRoots'];
    final Object? tools = json['tools'];
    final Object? env = json['shellEnv'];
    final Object? warnings = json['warnings'];
    return PluginInitResult(
      skills: <PluginSkill>[
        if (skills is List)
          for (final Object? item in skills)
            if (item is Map) PluginSkill.fromJson(item.cast<String, Object?>()),
      ],
      skillRoots: <String>[
        if (roots is List)
          for (final Object? item in roots) '$item',
      ],
      tools: <PluginToolSpec>[
        if (tools is List)
          for (final Object? item in tools)
            if (item is Map)
              PluginToolSpec.fromJson(item.cast<String, Object?>()),
      ],
      context: '${json['context'] ?? ''}',
      shellEnv: <String, String>{
        if (env is Map)
          for (final MapEntry<Object?, Object?> entry in env.entries)
            '${entry.key}': '${entry.value}',
      },
      warnings: <String>[
        if (warnings is List)
          for (final Object? item in warnings) '$item',
      ],
    );
  }
}

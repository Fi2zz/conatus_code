/// `.mcp.json`（Claude Code / OpenCode 生态的 `mcpServers` 形状）读取。
///
/// nava 自己的配置是 `~/.nava/config.toml`；本文件只做消费端适配：把项目根的
/// `.mcp.json` 映射成 [McpServerSpec]，与 TOML 声明合并（TOML 同名优先）。
/// 坏条目只告警跳过，不阻塞启动——外部配置不应该拖垮整个会话。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart' show resolveHomeDir;
import 'package:conatus_mcp/conatus_mcp.dart' show McpOAuthConfig;

import 'config_schema.dart';

/// 读取项目根 `.mcp.json` 里的 `mcpServers`；文件不存在返回空列表。
///
/// 项目根按最近的含 `.git` 的祖先目录判定（与技能发现同口径）；找不到时用
/// [workdir] 本身。[onWarning] 接收坏文件 / 坏条目的说明。
List<McpServerSpec> loadMcpJsonSpecs({
  required String workdir,
  void Function(String message)? onWarning,
}) {
  final File file = File(_path(_projectRoot(workdir), '.mcp.json'));
  return _loadSpecs(file, onWarning, sourceLabel: '项目 .mcp.json');
}

/// 读取全局 Claude Desktop 的 `claude_desktop_config.json`。
///
/// 查找顺序（后者覆盖前者同名 server）：macOS `~/Library/Application Support/
/// Claude/`、`~/.config/Claude/`、`~/.config/claude/`，以及 `%APPDATA%/Claude/`。
List<McpServerSpec> loadClaudeDesktopMcpSpecs({
  String? homeDir,
  Map<String, String>? env,
  void Function(String message)? onWarning,
}) {
  final Map<String, String> source = env ?? Platform.environment;
  final String home = homeDir ??
      (source['HOME']?.trim().isNotEmpty == true
          ? source['HOME']!.trim()
          : resolveHomeDir());
  final Map<String, McpServerSpec> merged = <String, McpServerSpec>{};
  for (final String path in _claudePaths(home, source)) {
    final File file = File(path);
    if (!file.existsSync()) continue;
    for (final McpServerSpec spec in _loadSpecs(
      file,
      onWarning,
      sourceLabel: 'Claude Desktop 配置',
    )) {
      merged[spec.name] = spec;
    }
  }
  return merged.values.toList(growable: false);
}

List<String> _claudePaths(String home, Map<String, String> env) {
  final List<String> paths = <String>[
    _path(home, 'Library/Application Support/Claude/claude_desktop_config.json'),
    _path(home, '.config/Claude/claude_desktop_config.json'),
    _path(home, '.config/claude/claude_desktop_config.json'),
  ];
  final String? appData = env['APPDATA']?.trim();
  if (appData != null && appData.isNotEmpty) {
    paths.add(_path(appData, 'Claude/claude_desktop_config.json'));
  }
  return paths;
}

List<McpServerSpec> _loadSpecs(
  File file,
  void Function(String message)? onWarning, {
  required String sourceLabel,
}) {
  if (!file.existsSync()) return const <McpServerSpec>[];
  final Object? decoded = _decode(file, onWarning);
  if (decoded is! Map) return const <McpServerSpec>[];
  final Object? servers = decoded['mcpServers'];
  if (servers is! Map) {
    _warn(onWarning, '${file.path} 缺少 mcpServers 表，已忽略。');
    return const <McpServerSpec>[];
  }
  final List<McpServerSpec> specs = <McpServerSpec>[];
  for (final MapEntry<Object?, Object?> entry in servers.entries) {
    final String name = entry.key.toString().trim();
    final McpServerSpec? spec = _specFrom(name, entry.value, onWarning);
    if (spec != null) specs.add(spec);
  }
  if (specs.isNotEmpty) {
    _warn(
      onWarning,
      '${file.path}：从 $sourceLabel 加载 ${specs.length} 台 MCP server'
      '（stdio 子进程不经沙箱，请确认来源可信）。',
    );
  }
  return specs;
}

/// 合并两批 server：同名时 [primary] 优先，[fallback] 的重复项告警后丢弃。
List<McpServerSpec> mergeMcpServerSpecs(
  List<McpServerSpec> primary,
  List<McpServerSpec> fallback, {
  void Function(String message)? onWarning,
  String primaryLabel = 'config.toml',
  String fallbackLabel = '.mcp.json',
}) {
  final Set<String> names = <String>{};
  final List<McpServerSpec> merged = <McpServerSpec>[];
  for (final McpServerSpec spec in primary) {
    names.add(spec.name);
    merged.add(spec);
  }
  for (final McpServerSpec spec in fallback) {
    if (names.add(spec.name)) {
      merged.add(spec);
      continue;
    }
    _warn(
      onWarning,
      'MCP server ${spec.name} 在 $primaryLabel 与 $fallbackLabel 重复，'
      '使用 $primaryLabel。',
    );
  }
  return merged;
}

/// config.toml 声明 + 项目 `.mcp.json` 的实际装配列表。
List<McpServerSpec> loadEffectiveMcpServers({
  required ConatusCodeConfig config,
  String? workdir,
  String? homeDir,
  Map<String, String>? env,
  bool includeClaudeDesktop = false,
  void Function(String message)? onWarning,
}) {
  final String dir = workdir ?? config.agent.workdir ?? Directory.current.path;
  final List<McpServerSpec> external = loadMcpJsonSpecs(
    workdir: dir,
    onWarning: onWarning,
  );
  final List<McpServerSpec> merged = mergeMcpServerSpecs(
    config.mcp.servers,
    external,
    onWarning: onWarning,
  );
  if (!includeClaudeDesktop) return merged;
  final List<McpServerSpec> desktop = loadClaudeDesktopMcpSpecs(
    homeDir: homeDir,
    env: env,
    onWarning: onWarning,
  );
  return mergeMcpServerSpecs(
    merged,
    desktop,
    onWarning: onWarning,
    primaryLabel: 'config.toml / .mcp.json',
    fallbackLabel: 'claude_desktop_config.json',
  );
}

Object? _decode(File file, void Function(String message)? onWarning) {
  try {
    return jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    _warn(onWarning, '${file.path} 解析失败：${error.message}');
  } on FileSystemException catch (error) {
    _warn(onWarning, '${file.path} 读取失败：${error.message}');
  }
  return null;
}

McpServerSpec? _specFrom(
  String name,
  Object? raw,
  void Function(String message)? onWarning,
) {
  if (raw is! Map) {
    _warn(onWarning, '.mcp.json 的 $name 必须是表，已跳过。');
    return null;
  }
  final String? command = _string(raw['command']);
  final String? url = _string(raw['url']);
  final McpServerType? type = _type(raw['type'], command, url);
  if (type == null) {
    _warn(onWarning, '.mcp.json 的 $name 缺少 command / url 或 type 非法，已跳过。');
    return null;
  }
  if (type == McpServerType.stdio && command == null) {
    _warn(onWarning, '.mcp.json 的 $name 是 stdio 但缺少 command，已跳过。');
    return null;
  }
  if (type != McpServerType.stdio && url == null) {
    _warn(onWarning, '.mcp.json 的 $name 是远程 server 但缺少 url，已跳过。');
    return null;
  }
  final bool stdio = type == McpServerType.stdio;
  return McpServerSpec(
    name: name,
    type: type,
    command: stdio ? command : null,
    args: stdio ? _stringList(raw['args']) : const <String>[],
    env: stdio ? _stringMap(raw['env']) : const <String, String>{},
    url: stdio ? null : url,
    headers: stdio ? const <String, String>{} : _stringMap(raw['headers']),
    oauth: _oauth(raw['oauth']),
  );
}

McpServerType? _type(Object? raw, String? command, String? url) {
  if (raw == null) {
    if (command != null) return McpServerType.stdio;
    if (url != null) return McpServerType.http;
    return null;
  }
  if (raw is! String) return null;
  return switch (raw.trim()) {
    'stdio' => McpServerType.stdio,
    'sse' => McpServerType.sse,
    'http' || 'streamable-http' || 'streamableHttp' => McpServerType.http,
    _ => null,
  };
}

McpOAuthConfig? _oauth(Object? raw) {
  if (raw is! bool) return null;
  return McpOAuthConfig(enabled: raw);
}

String? _string(Object? raw) {
  if (raw is! String) return null;
  final String trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return <String>[for (final Object? item in raw) if (item is String) item];
}

Map<String, String> _stringMap(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  final Map<String, String> result = <String, String>{};
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    if (entry.key is String && entry.value is String) {
      result[entry.key as String] = entry.value as String;
    }
  }
  return result;
}

/// 最近的含 `.git` 的祖先目录；找不到时返回 [start]。
///
/// `.git` 既可能是目录，也可能是工作树 / 子模块里的 gitfile，两者都算项目根。
String _projectRoot(String start) {
  String current = start;
  while (true) {
    final String git = _path(current, '.git');
    if (Directory(git).existsSync() || File(git).existsSync()) return current;
    final String parent = Directory(current).parent.path;
    if (parent == current) return start;
    current = parent;
  }
}

String _path(String base, String relative) =>
    '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';

void _warn(void Function(String message)? onWarning, String message) {
  onWarning?.call(message);
}

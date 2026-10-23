/// 自定义 Agent 发现与注册表。
///
/// 发现顺序由低到高：全局 OpenCode → 全局 nava → 项目 OpenCode → 项目
/// nava；同 ID 后者覆盖前者。内置 Agent 先注册，自定义同名覆盖。`.opencode`
/// 只读：这里只 `exists` / `list` / `readAsString`，不创建目录、不写缓存。
library;

import 'dart:io';

import 'agent_builtins.dart';
import 'agent_definition.dart';
import 'agent_parser.dart';

/// Agent 注册表：解析后的定义按 ID 索引。
class AgentRegistry {
  AgentRegistry._(this._defaultId);

  final String? _defaultId;
  final Map<String, AgentDefinition> _agents = <String, AgentDefinition>{};
  final List<String> _warnings = <String>[];
  bool _defaultWarningAdded = false;

  /// 加载内置 Agent 与四层 Agent 目录；单条损坏不影响其余 Agent。
  static Future<AgentRegistry> load({
    required String workdir,
    String? home,
    String? defaultId,
  }) async {
    final AgentRegistry registry = AgentRegistry._(defaultId);
    for (final AgentDefinition agent in kBuiltinAgents) {
      registry.add(agent);
    }
    for (final String root in _agentRoots(workdir: workdir, home: home)) {
      await registry._loadRoot(root);
    }
    return registry;
  }

  /// 按 ID 精确查找；未命中返回 `null`（hidden Agent 同样可解析）。
  AgentDefinition? byId(String id) => _agents[id.trim()];

  /// 全部 Agent（含 hidden / subagent），按 ID 排序。
  List<AgentDefinition> get all => _sorted(_agents.values);

  /// 选择器可见的 Agent（不含 hidden），按 ID 排序。
  List<AgentDefinition> get visible =>
      _sorted(_agents.values.where((AgentDefinition agent) => !agent.hidden));

  /// 可作为子 Agent 的可见 Agent，按 ID 排序。
  List<AgentDefinition> get subagents => _sorted(
    _agents.values.where(
      (AgentDefinition agent) =>
          !agent.hidden && agent.mode != AgentMode.primary,
    ),
  );

  /// 新会话默认 Agent：配置值优先；不可作为主 Agent 时回退。
  AgentDefinition get defaultAgent {
    final String? requested = _defaultId?.trim();
    if (requested != null && requested.isNotEmpty) {
      final AgentDefinition? chosen = byId(requested);
      if (chosen != null && chosen.mode != AgentMode.subagent) return chosen;
      if (chosen != null) _warnSubagentDefault(requested);
    }
    final AgentDefinition? build = byId('build');
    if (build != null && build.mode != AgentMode.subagent) return build;
    for (final AgentDefinition agent in visible) {
      if (agent.mode != AgentMode.subagent) return agent;
    }
    throw StateError('没有可用作主 Agent 的定义');
  }

  void _warnSubagentDefault(String id) {
    if (_defaultWarningAdded) return;
    _defaultWarningAdded = true;
    _warnings.add('默认 Agent "$id" 是 subagent，已回退到可用的主 Agent');
  }

  /// 加载期间跳过的文件说明；供 TUI / `/doctor` 诊断。
  List<String> get warnings => List<String>.unmodifiable(_warnings);

  /// 注册或覆盖一个 Agent（内置与动态来源用）。
  void add(AgentDefinition agent) {
    final String id = agent.id.trim();
    if (id.isEmpty) return;
    _agents[id] = agent;
  }

  Future<void> _loadRoot(String root) async {
    final Directory directory = Directory(root);
    if (!await directory.exists()) return;
    final List<String> files = <String>[];
    try {
      // 默认 followLinks: true，dotfile 管理器创建的符号链接 Agent 也能发现。
      await for (final FileSystemEntity entity in directory.list(
        recursive: true,
      )) {
        if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
          files.add(entity.path);
        }
      }
    } on FileSystemException catch (error) {
      _warnings.add('无法读取 Agent 目录 $root: ${error.message}');
      return;
    }
    files.sort();
    for (final String file in files) {
      await _loadFile(root, file);
    }
  }

  Future<void> _loadFile(String root, String path) async {
    final String id = _agentId(root, path);
    final String text;
    try {
      text = await File(path).readAsString();
    } on FileSystemException catch (error) {
      _warnings.add('无法读取 Agent 文件 $path: ${error.message}');
      return;
    }
    final AgentParseResult result = parseAgentDocumentDetailed(
      text,
      id: id,
      sourcePath: path,
    );
    final AgentDefinition? agent = result.definition;
    for (final String warning in result.warnings) {
      _warnings.add('Agent 文件 $path: $warning');
    }
    if (agent == null) {
      _warnings.add('跳过 Agent 文件 $path: ${result.error}');
      return;
    }
    _agents[agent.id] = agent;
  }
}

List<AgentDefinition> _sorted(Iterable<AgentDefinition> agents) {
  final List<AgentDefinition> sorted = agents.toList(growable: false);
  sorted.sort(
    (AgentDefinition left, AgentDefinition right) =>
        left.id.compareTo(right.id),
  );
  return sorted;
}

/// 四层目录，低优先级在前。
List<String> _agentRoots({required String workdir, String? home}) {
  final List<String> roots = <String>[];
  final String? homeDir = _homeDirectory(home);
  if (homeDir != null) {
    roots.add('$homeDir/.config/opencode/agents');
    roots.add('$homeDir/.nava/agents');
  }
  roots.add('$workdir/.opencode/agents');
  roots.add('$workdir/.nava/agents');
  return roots;
}

/// `home` 显式值优先，其次 `HOME` / `USERPROFILE`；定位不到时只扫项目层。
String? _homeDirectory(String? home) {
  final String? explicit = _nonEmpty(home);
  if (explicit != null) return explicit;
  final Map<String, String> env = Platform.environment;
  return _nonEmpty(env['HOME']) ?? _nonEmpty(env['USERPROFILE']);
}

String? _nonEmpty(String? value) {
  final String? trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// 文件路径相对 Agent 根目录 → Agent ID（分隔符统一为 `/`，去掉 `.md`）。
String _agentId(String root, String path) {
  String relative = path.substring(root.length).replaceAll('\\', '/');
  while (relative.startsWith('/')) {
    relative = relative.substring(1);
  }
  return relative.toLowerCase().endsWith('.md')
      ? relative.substring(0, relative.length - 3)
      : relative;
}

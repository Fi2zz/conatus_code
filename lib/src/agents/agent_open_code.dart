/// OpenCode 兼容映射：权限动作名与工具名。
///
/// OpenCode 的 Agent frontmatter 用 `bash` / `write` / `patch` 等动作名，工具
/// 名也与 nava 不同；解析时统一归一到 nava 的动作 / 工具标识。未知名称原样
/// 保留，便于自定义工具继续工作。
library;

import 'package:conatus_agent/conatus_agent.dart' show permissionActionFor;

/// OpenCode 权限动作 → nava 权限动作。
const Map<String, String> _openCodeActions = <String, String>{
  'bash': 'shell',
  'write': 'edit',
  'patch': 'edit',
  'edit': 'edit',
  'read': 'read',
  'grep': 'grep',
  'glob': 'glob',
  'webfetch': 'webfetch',
  'websearch': 'websearch',
  'subagent': 'subagent',
  'skill': 'skill',
};

/// nava 已知的权限动作（与 `permission_action.dart` 的动作表一致）。
const Set<String> _knownActions = <String>{
  'read',
  'edit',
  'shell',
  'grep',
  'glob',
  'webfetch',
  'websearch',
  'subagent',
  'skill',
  'question',
  'external_directory',
};

/// OpenCode 工具名 → nava 工具名。
const Map<String, String> _openCodeTools = <String, String>{
  'read': 'read_file',
  'write': 'write_file',
  'edit': 'edit_file',
  'patch': 'apply_patch',
  'bash': 'run_command',
  'grep': 'rg',
  'glob': 'glob',
  'webfetch': 'fetch_url',
  'websearch': 'web_search',
  'subagent': 'spawn_agent',
  'skill': 'skill',
};

/// 把 OpenCode / 工具名形式的动作归一为 nava 权限动作。
String normalizeAgentAction(String raw) {
  final String trimmed = raw.trim();
  return permissionActionFor(_openCodeActions[trimmed] ?? trimmed);
}

/// 动作名是否已知；MCP 风格（含 `__`）视为已知。
bool agentActionKnown(String raw, String normalized) {
  final String trimmed = raw.trim();
  return trimmed.contains('__') ||
      _openCodeActions.containsKey(trimmed) ||
      _knownActions.contains(normalized);
}

/// 把 OpenCode 工具名归一为 nava 工具名；未知名称原样返回。
String mapAgentToolName(String raw) {
  final String trimmed = raw.trim();
  return _openCodeTools[trimmed] ?? trimmed;
}

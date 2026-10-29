/// OpenCode 兼容映射：权限动作名。
///
/// nava 的工具标识与权限动作已与 OpenCode 对齐（`bash` / `read` / `edit` /
/// `task` …）；这里只保留历史动作名的归并（`write` / `patch` → `edit`，
/// `list` → `read`）。未知名称原样保留，便于自定义工具继续工作。
library;

import 'package:conatus_agent/conatus_agent.dart' show permissionActionFor;

/// OpenCode 动作名 → nava 权限动作。
const Map<String, String> _openCodeActions = <String, String>{
  'write': 'edit',
  'patch': 'edit',
  'list': 'read',
};

/// OpenCode 有、但 nava 没有对应工具的权限动作；保留规则只会永不命中。
const Set<String> _unsupportedActions = <String>{
  'todoread',
  'lsp',
};

/// nava 已知的权限动作（与 `permission_action.dart` 的动作表一致）。
const Set<String> _knownActions = <String>{
  'read',
  'edit',
  'bash',
  'grep',
  'glob',
  'webfetch',
  'websearch',
  'task',
  'skill',
  'question',
  'todowrite',
  'external_directory',
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

/// nava 是否有对应工具承接该 OpenCode 动作。
bool agentActionSupported(String raw) =>
    !_unsupportedActions.contains(raw.trim());

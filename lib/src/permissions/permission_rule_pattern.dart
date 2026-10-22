/// 「总是允许」的规则推导：把一次审批请求折成可持久化的 [PermissionRule]。
///
/// 粒度按动作区分：
/// - shell：命令前缀（第一个空白前）+ ` *`，覆盖同一命令的不同参数；
/// - 路径类：所在目录 + `/*`；
/// - MCP / 其余：动作 + 通配 `*`。
///
/// 只做字符串推导，不做路径规范化（与匹配器一致）；相对路径按原样取父目录。
library;

import 'package:conatus_agent/conatus_agent.dart';

/// 默认规则来源标记。
const String kRememberedRuleSource = 'project';

/// 由审批请求推导一条 `allow` 规则。
PermissionRule permissionRuleFor(ApprovalRequest request) {
  final String action = request.action.isEmpty
      ? permissionActionFor(request.toolName)
      : request.action;
  return PermissionRule(
    action: action,
    resource: _resourceFor(request, action),
    effect: PermissionEffect.allow,
    source: kRememberedRuleSource,
  );
}

String _resourceFor(ApprovalRequest request, String action) {
  if (action == 'shell') return _commandPattern(request.resources);
  if (request.pathArgs.isNotEmpty) {
    return _directoryPattern(request.pathArgs.first);
  }
  return '*';
}

/// 命令前缀 + ` *`；取不到命令时退化为 `*`。
String _commandPattern(List<String> resources) {
  final String command = resources.isEmpty ? '' : resources.first.trim();
  if (command.isEmpty) return '*';
  final String head = command.split(RegExp(r'\s+')).first;
  return head.isEmpty ? '*' : '$head *';
}

/// 所在目录 + `/*`；拿不到目录层级时退化为 `*`。
String _directoryPattern(String path) {
  final String normalized = path.replaceAll('\\', '/');
  final int cut = normalized.lastIndexOf('/');
  if (cut < 0) return '*';
  return '${normalized.substring(0, cut)}/*';
}

/// 「总是允许」的规则推导：把一次审批请求折成可持久化的 [PermissionRule]。
///
/// 只保存**具体资源**，绝不保存通配 `*` 的 allow（否则会覆盖 config / project
/// 里的 deny，且用户看不到影响面）：
/// - shell：命令前缀（第一个空白前）+ ` *`，覆盖同一命令的不同参数；
/// - 路径 / glob / web / skill / subagent：按中间件规范化后的每个资源各存一条；
/// - MCP / question / 无具体资源：返回空列表（调用方保持会话级放行）。
///
/// 规则来源标记为 `project`，由 `PermissionWiring` 追加到 config 之后。
library;

import 'package:conatus_agent/conatus_agent.dart';

/// 默认规则来源标记。
const String kRememberedRuleSource = 'project';

/// 由审批请求推导可持久化的 allow 规则（可能多条）。
List<PermissionRule> permissionRulesFor(ApprovalRequest request) {
  final String action = request.action.isEmpty
      ? permissionActionFor(request.toolName)
      : request.action;
  final List<String> resources = _concreteResources(request.resources, action);
  if (resources.isEmpty) return const <PermissionRule>[];
  if (action == 'bash') {
    final String head = resources.first.split(RegExp(r'\s+')).first;
    if (head.isEmpty) return const <PermissionRule>[];
    return <PermissionRule>[_rule(action, '$head *')];
  }
  return <PermissionRule>[
    for (final String resource in resources) _rule(action, resource),
  ];
}

/// 第一条可持久化规则；没有具体资源时为 `null`。
PermissionRule? permissionRuleFor(ApprovalRequest request) {
  final List<PermissionRule> rules = permissionRulesFor(request);
  return rules.isEmpty ? null : rules.first;
}

PermissionRule _rule(String action, String resource) => PermissionRule(
  action: action,
  resource: resource,
  effect: PermissionEffect.allow,
  source: kRememberedRuleSource,
);

/// 过滤掉通配与空值；路径动作先规范化。
List<String> _concreteResources(List<String> resources, String action) {
  final List<String> concrete = <String>[];
  for (final String raw in resources) {
    final String value = permissionActionUsesPath(action)
        ? normalizePermissionPath(raw)
        : raw.trim();
    if (value.isEmpty || value == '*') continue;
    if (!concrete.contains(value)) concrete.add(value);
  }
  return concrete;
}

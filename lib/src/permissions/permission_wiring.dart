/// nava 侧的权限作用域装配：规则来源合成 + 「总是允许」落盘。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// 把 `config → project → session` 规则与当前权限模式合成为一个
/// [PermissionScope]。
///
/// [slot] 是根上下文里的 [kPermissionScopeService] 服务；权限中间件只读它，
/// 因此会话切换 / 权限模式切换只改这里，不重挂中间件。会话内临时放行（「总是
/// 允许该工具」「信任此文件夹」）仍留在 [TuiPermissionGate] 里，不写进作用域。
class PermissionWiring {
  /// 创建装配；[store] 指向项目数据目录下的 `permissions.json`。
  PermissionWiring({
    required this.store,
    this.configRules = const <PermissionRule>[],
  });

  /// 项目级持久化存储（`~/.nava/projects/<hash>/permissions.json`）。
  final PermissionStore store;

  /// `[[permissions]]` 只读基线。
  final List<PermissionRule> configRules;

  /// 根上下文里的可替换作用域槽位。
  final PermissionScopeSlot slot = PermissionScopeSlot();

  List<PermissionRule> _projectRules = <PermissionRule>[];
  List<PermissionRule> _sessionRules = <PermissionRule>[];
  ToolRisk? _askThreshold = ToolRisk.high;
  String _agentId = 'build';

  /// 当前合成后的规则（config → project → session）。
  List<PermissionRule> get rules => List<PermissionRule>.unmodifiable(
        <PermissionRule>[...configRules, ..._projectRules, ..._sessionRules],
      );

  /// 载入项目规则；文件缺失 / 损坏时按空规则处理（不阻塞启动）。
  Future<void> load() async {
    _projectRules = _normalizeRules(await store.load());
    _publish();
  }

  /// 替换会话级规则（切会话时由控制器设为空列表）。
  void setSessionRules(List<PermissionRule> rules) {
    _sessionRules = _normalizeRules(rules);
    _publish();
  }

  /// 更新权限模式阈值与 Agent 标识（会话绑定时调用）。
  void applyMode({required ToolRisk? askThreshold, required String agentId}) {
    _askThreshold = askThreshold;
    _agentId = agentId;
    _publish();
  }

  /// 追加规则并落盘；成功返回 `null`，拒绝或失败返回面向用户的警告。
  ///
  /// 落盘前检查已有 deny：新 allow 若会覆盖某条 deny，则整体拒绝（仅保留会话
  /// 放行），避免「总是允许」悄悄改变全局策略。失败时**不**更新作用域。
  Future<String?> remember(
    List<PermissionRule> rules,
    List<String> resources,
  ) async {
    if (rules.isEmpty) return null;
    final List<PermissionRule> normalized = _normalizeRules(rules);
    final PermissionRule? conflict = _denyConflict(normalized, resources);
    if (conflict != null) {
      return '已有拒绝规则 ${conflict.toString()}，本次仅会话放行';
    }
    try {
      for (final PermissionRule rule in normalized) {
        await store.add(rule);
      }
    } on PermissionStoreException catch (error) {
      return error.message;
    } on FileSystemException catch (error) {
      return error.message;
    } on ProcessException catch (error) {
      return error.message;
    }
    _projectRules = <PermissionRule>[..._projectRules, ...normalized];
    _publish();
    return null;
  }

  /// 找出会被 [rules] 覆盖的 deny；按被批准的具体 [resources] 判断。
  PermissionRule? _denyConflict(
    List<PermissionRule> rules,
    List<String> resources,
  ) {
    final List<PermissionRule> existing = _normalizeRules(<PermissionRule>[
      ...configRules,
      ..._projectRules,
      ..._sessionRules,
    ]);
    for (final PermissionRule rule in rules) {
      for (final PermissionRule current in existing) {
        if (current.action != rule.action) continue;
        if (current.effect != PermissionEffect.deny) continue;
        for (final String resource in resources) {
          if (permissionPatternMatches(current.resource, resource)) {
            return current;
          }
        }
      }
    }
    return null;
  }

  void _publish() {
    slot.set(PermissionScope(
      rules: rules,
      askThreshold: _askThreshold,
      agentId: _agentId,
    ));
  }

  /// 路径动作的规则资源也规范化（兼容手写 `~` / `./`）。
  List<PermissionRule> _normalizeRules(List<PermissionRule> rules) =>
      <PermissionRule>[
        for (final PermissionRule rule in rules)
          permissionActionUsesPath(rule.action)
              ? PermissionRule(
                  action: rule.action,
                  resource: normalizePermissionPath(rule.resource),
                  effect: rule.effect,
                  source: rule.source,
                )
              : rule,
      ];
}

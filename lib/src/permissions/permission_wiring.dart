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
///
/// [workdir] 用于把规则里的相对路径解析成绝对路径（`edit "src/*"` 必须能匹配
/// `write_file("/abs/work/src/x")`）；判定器还会补真实路径拼写。库用法可以
/// 不传，此时只做词法规范化。
class PermissionWiring {
  /// 创建装配；[store] 指向项目数据目录下的 `permissions.json`。
  PermissionWiring({
    required this.store,
    this.workdir,
    List<PermissionRule> configRules = const <PermissionRule>[],
  }) : configRules = _normalizeRules(configRules, workdir);

  /// 项目级持久化存储（`~/.nava/workspaces/<basename>-<hash>/permissions.json`）。
  final PermissionStore store;

  /// 工作区根（规则相对路径的解析基准）；`null` 时只做词法规范化。
  final String? workdir;

  /// `[[permissions]]` 只读基线。
  final List<PermissionRule> configRules;

  /// 根上下文里的可替换作用域槽位。
  final PermissionScopeSlot slot = PermissionScopeSlot();

  List<PermissionRule> _projectRules = <PermissionRule>[];
  List<PermissionRule> _sessionRules = <PermissionRule>[];
  List<PermissionRule> _agentRules = <PermissionRule>[];
  ToolRisk? _askThreshold = ToolRisk.high;
  String _agentId = 'build';

  /// 最近一次 [load] 的失败原因（文件损坏时为非空）；正常为 `null`。
  String? get loadError => _loadError;
  String? _loadError;

  /// 最近一次 [load] 跳过的非法规则条数。
  int get skippedRules => _skippedRules;
  int _skippedRules = 0;

  /// 当前合成后的规则（config → project → session → agent）。
  List<PermissionRule> get rules =>
      List<PermissionRule>.unmodifiable(<PermissionRule>[
        ...configRules,
        ..._projectRules,
        ..._sessionRules,
        ..._agentRules,
      ]);

  /// 载入项目规则；文件缺失 / 损坏时按空规则处理（不阻塞启动），
  /// 但把失败原因留在 [loadError] 供启动提示与 `/doctor` 展示。
  Future<void> load() async {
    _projectRules = _normalizeRules(await store.load(), workdir);
    _loadError = store.loadError;
    _skippedRules = store.skippedRules;
    _publish();
  }

  /// 替换会话级规则（切会话时由控制器设为空列表）。
  void setSessionRules(List<PermissionRule> rules) {
    _sessionRules = _normalizeRules(rules, workdir);
    _publish();
  }

  /// 替换当前 Agent 自带规则；**只收紧**：丢弃 `allow`，只保留 `deny` / `ask`。
  ///
  /// Agent 规则追加在 config → project → session 之后，因此 deny 覆盖前面的
  /// allow；反向放宽（Agent 的 allow 覆盖项目 deny）被直接过滤掉。
  void setAgentRules(List<PermissionRule> rules) {
    _agentRules = _normalizeRules(<PermissionRule>[
      for (final PermissionRule rule in rules)
        if (rule.effect != PermissionEffect.allow) rule,
    ], workdir);
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
    final List<PermissionRule> normalized = _normalizeRules(rules, workdir);
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
  ///
  /// shell 规则额外做**字面前缀交集**：`deny "git push origin *"` 比
  /// `allow "git push *"` 更具体，若只做「allow pattern 是否匹配 deny pattern」
  /// 的检查，后者会先落盘、把前者的 deny 覆盖掉——用户批准的只是
  /// `git push --tags`，不该顺带放行所有 `git push`。
  PermissionRule? _denyConflict(
    List<PermissionRule> rules,
    List<String> resources,
  ) {
    final List<PermissionRule> existing = _normalizeRules(<PermissionRule>[
      ...configRules,
      ..._projectRules,
      ..._sessionRules,
      ..._agentRules,
    ], workdir);
    for (final PermissionRule rule in rules) {
      for (final PermissionRule current in existing) {
        if (current.action != rule.action) continue;
        if (current.effect != PermissionEffect.deny) continue;
        if (rule.action == 'shell') {
          if (permissionPatternMatches(rule.resource, current.resource)) {
            return current;
          }
          final String head = _literalPrefix(rule.resource);
          if (head.isNotEmpty &&
              _literalPrefix(current.resource).startsWith(head)) {
            return current;
          }
        }
        for (final String resource in resources) {
          if (permissionPatternMatches(current.resource, resource)) {
            return current;
          }
        }
      }
    }
    return null;
  }

  /// pattern 里第一个通配符之前的字面前缀（`git push *` → `git push `）。
  static String _literalPrefix(String pattern) {
    final int star = pattern.indexOf('*');
    final int question = pattern.indexOf('?');
    final int cut = star < 0
        ? question
        : question < 0
        ? star
        : (star < question ? star : question);
    return cut < 0 ? pattern : pattern.substring(0, cut);
  }

  void _publish() {
    slot.set(
      PermissionScope(
        rules: rules,
        askThreshold: _askThreshold,
        agentId: _agentId,
      ),
    );
  }

  /// 路径动作的规则资源按 [workdir] 解析（兼容 `~` / `./` / 相对路径）。
  ///
  /// 规则保留为**单条**解析后的 pattern：调用侧资源会同时给出词法 / workdir /
  /// 真实路径三种拼写（见 `permissionPathSpellings`），单条绝对 pattern 足以
  /// 命中，不会让规则条数因拼写而膨胀。
  static List<PermissionRule> _normalizeRules(
    List<PermissionRule> rules,
    String? workdir,
  ) => <PermissionRule>[
    for (final PermissionRule rule in rules)
      permissionActionUsesPath(rule.action)
          ? PermissionRule(
              action: rule.action,
              resource: workdir == null || workdir.isEmpty
                  ? normalizePermissionPath(rule.resource)
                  : resolvePermissionPath(rule.resource, workdir),
              effect: rule.effect,
              source: rule.source,
              configuredResource: rule.displayResource,
            )
          : rule,
  ];
}

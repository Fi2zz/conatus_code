/// nava 侧的权限作用域装配：规则来源合成 + 「总是允许」落盘。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// 把 `config → project` 规则与当前权限模式合成为一个 [PermissionScope]。
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
  ToolRisk? _askThreshold = ToolRisk.high;
  String _agentId = 'build';

  /// 载入项目规则；文件缺失 / 损坏时按空规则处理（不阻塞启动）。
  Future<void> load() async {
    _projectRules = await store.load();
    _publish();
  }

  /// 更新权限模式阈值与 Agent 标识（会话绑定时调用）。
  void applyMode({required ToolRisk? askThreshold, required String agentId}) {
    _askThreshold = askThreshold;
    _agentId = agentId;
    _publish();
  }

  /// 追加一条规则并落盘；成功返回 `null`，失败返回面向用户的警告。
  ///
  /// 失败时**不**更新作用域：调用方应保留会话内临时放行，并提示用户项目文件
  /// 未被改动（损坏文件不会被「总是允许」覆盖）。
  Future<String?> remember(PermissionRule rule) async {
    try {
      await store.add(rule);
    } on PermissionStoreException catch (error) {
      return error.message;
    } on Object catch (error) {
      return '$error';
    }
    _projectRules = <PermissionRule>[..._projectRules, rule];
    _publish();
    return null;
  }

  void _publish() {
    slot.set(
      PermissionScope(
        rules: <PermissionRule>[...configRules, ..._projectRules],
        askThreshold: _askThreshold,
        agentId: _agentId,
      ),
    );
  }
}

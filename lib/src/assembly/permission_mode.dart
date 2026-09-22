/// 配置里的审批模式 → TUI 三档权限模式的映射。
///
/// 配置层不认识 TUI 类型，TUI 也不认识配置类型，映射放在装配层。
library;

import '../config/config_schema.dart';
import '../tui/tui_permission.dart';

/// 把 [ApprovalMode] 映射为 TUI 的权限模式。
TuiPermissionMode toTuiPermissionMode(ApprovalMode mode) => switch (mode) {
      ApprovalMode.alwaysAsk => TuiPermissionMode.alwaysAsk,
      ApprovalMode.askWhenNeeded => TuiPermissionMode.askWhenNeeded,
      ApprovalMode.neverAsk => TuiPermissionMode.neverAsk,
    };

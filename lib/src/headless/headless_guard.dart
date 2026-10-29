/// headless 启动前的审批语义提示。
///
/// headless（`-p`）跑的是**无人值守**轮次——不装 TUI 浮层，自然也没有审批人；
/// 权限判定为 `ask` 的工具会被直接拒绝（`PERMISSION_ASK_UNATTENDED`）。这些提示
/// 把「你配的审批档位在 `-p` 下会变成什么」在启动期说清楚，而不是让模型反复
/// 重试、用户以为工具坏了。
library;

import '../config/config_schema.dart';

/// headless 下 `always_ask` 的实际后果提示；无需提示时返回 `null`。
///
/// 只提示 `always_ask`：它是用户**显式加严**的审批姿态（缺省是
/// `ask_when_needed`），在 `-p` 下会表现为「medium 及以上工具直接被拒绝」
/// （`PERMISSION_ASK_UNATTENDED`）。与其让用户以为「每次都会被问」，不如
/// 启动时把这条规则说清楚。
String? approvalModeIgnoredNotice({
  required bool headless,
  required ApprovalConfig approval,
}) {
  if (!headless) return null;
  if (approval.mode != ApprovalMode.alwaysAsk) return null;
  return '提示：headless 无人应答审批——approval.mode = "always_ask" 下需要确认的'
      '工具会被直接拒绝（PERMISSION_ASK_UNATTENDED）。需要逐次批准请改用 TUI。';
}

/// headless 缺省档（`ask_when_needed`）的后果提示，一行即可。
///
/// 缺省阈值为 high：`run_command` / `apply_patch` / `git_commit` 这类工具在
/// `-p` 下不会弹窗，而是直接被拒。用户看到的是「模型说它要跑命令，然后什么
/// 也没发生」——启动时说清楚，比让模型反复重试有用。
String? headlessAskNotice({
  required bool headless,
  required ApprovalConfig approval,
}) {
  if (!headless || approval.mode == ApprovalMode.neverAsk) return null;
  if (approval.mode == ApprovalMode.alwaysAsk) return null;
  return '提示：headless 无人应答审批——ask_when_needed 下 high 风险工具'
      '（run_command / apply_patch / git_commit 等）会被直接拒绝'
      '（PERMISSION_ASK_UNATTENDED）。需要它们运行请配置 [[permissions]] allow，'
      '或在无人值守环境显式设 [approval] mode = "never_ask"。';
}

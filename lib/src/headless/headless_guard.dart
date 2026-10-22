/// headless 启动前的安全闸门（E-9）：无人值守 + 无审批链 + 无 OS 沙箱 = 裸奔。
///
/// 为什么需要它：headless（`-p`）跑的是**无人值守**轮次——不装 TUI 浮层，
/// 自然也没有审批人；权限判定为 `ask` 的工具会被直接拒绝
/// （`PERMISSION_ASK_UNATTENDED`）。此时真正能执行高风险动作的只剩 OS 沙箱
/// （Layer 2）。所以当沙箱被显式关掉（`enabled = false` 或
/// `preset = "danger_full_access"`，两者最终都让 shell 回到本地直执），
/// headless 就必须显式确认风险才放行：`ask` 拒绝只挡「需要人点头」的调用，
/// 显式 `allow`（`askThreshold: null` / 规则）仍会真的执行。
///
/// 闸门放在启动期而非运行期：早失败给出可行动的错误，比跑一半被攻击面
/// 暴露更负责；同时不改变 TUI 与库用法（`ConatusTuiRuntime.create` 不受限）。
library;

import '../config/config_schema.dart';

/// headless 安全检查：返回拒绝启动的错误消息；可放行时返回 `null`。
///
/// 放行条件：非 headless（TUI 有审批链）、显式传了 [allowUnsafe]、或 OS 沙箱
/// 照常生效。判断顺序即「先看模式，再看确认，最后看沙箱」。
String? validateHeadlessSafety({
  required bool headless,
  required SandboxSettings sandbox,
  required bool allowUnsafe,
}) {
  if (!headless || allowUnsafe) return null;
  final String? reason = sandboxDisabledReason(sandbox);
  if (reason == null) return null;
  return 'headless 拒绝启动：`-p` 不装审批链（无人可应答），而 $reason，'
      '高危工具将无人值守直接执行。\n'
      '  修复方式：改用 TUI（去掉 -p）、恢复 OS 沙箱'
      '（[sandbox] enabled = true 且 preset = "workspace_write"），\n'
      '  或确认风险后追加 --allow-unsafe-headless 显式放行。';
}

/// OS 沙箱（Layer 2）被关掉的原因描述；照常生效时返回 `null`。
///
/// 两种关闭方式殊途同归——`resolveSandboxLayers` 对它们都返回 `shell: null`
/// （回本地直执），因此按同一档风险处理。
String? sandboxDisabledReason(SandboxSettings sandbox) {
  if (!sandbox.enabled) return '[sandbox] enabled = false（OS 沙箱已关闭）';
  if (sandbox.preset == SandboxPreset.dangerFullAccess) {
    return '[sandbox] preset = "danger_full_access"（OS 沙箱已被预设关掉）';
  }
  return null;
}

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
      '或在无人值守环境显式设 [approval] mode = "never_ask"（配合沙箱）。';
}

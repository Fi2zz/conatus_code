/// conatus 的 nocterm 文本 TUI：会话控制器、斜杠命令、会话选择面板与渲染组件。
///
/// 用 [ConatusTuiRuntime] 装配好 conatus 服务后，把 [ConatusTuiController] 交给
/// [AgentTui] 渲染，即可得到一个可直接运行的对话式终端界面。
///
/// 本库把 `nocterm` 的 API 一并再导出：挂载界面要用 `runApp` / `shutdownApp`，
/// 自定义视图要用 `Component` / `Text` 这些类型，调用方因此不必在自己的
/// `pubspec.yaml` 里再声明 `nocterm`。
///
/// 只屏蔽 nocterm 自带的两个终端 matcher（`isEmpty` / `isNotEmpty`）——它们与
/// `package:test` 的同名 matcher 冲突，需要时直接依赖 nocterm 用前缀引入。
library;

export 'package:nocterm/nocterm.dart' hide isEmpty, isNotEmpty;

export 'src/tui/ask_user_tool.dart'
    show
        AskUserTool,
        TuiUserPromptHost,
        kAskUserPurposePermissionMode,
        kAskUserTimeout,
        kAskUserToolName;
export 'src/tui/at_ref.dart' show expandAtRefs, kAtRefMaxBytes, kAtRefMaxCount;
export 'src/tui/at_ref_menu.dart';
export 'src/tui/at_ref_menu_view.dart';
export 'src/tui/team_snapshot.dart';
export 'src/tui/team_subscription.dart';
export 'src/tui/team_views.dart';
export 'src/tui/transcript.dart';
export 'src/tui/tui.dart';
export 'src/tui/tui_app.dart';
export 'src/tui/tui_choice.dart';
export 'src/tui/tui_choice_view.dart';
export 'src/tui/tui_chrome.dart';
export 'src/tui/tui_command_menu_view.dart';
export 'src/tui/tui_commands.dart';
export 'src/tui/tui_controller.dart'
    show ConatusTuiController, kManualCompactKeepRecent, kMessageQueueCap;
export 'src/tui/tui_copy.dart';
export 'src/tui/tui_form.dart';
export 'src/tui/tui_form_view.dart';
export 'src/tui/tui_help.dart';
export 'src/tui/tui_message.dart';
export 'src/tui/tui_model.dart';
export 'src/tui/tui_model_view.dart';
export 'src/tui/tui_options.dart';
export 'src/tui/tui_permission.dart';
export 'src/tui/tui_permission_gate.dart'
    show
        TuiPermissionGate,
        kApprovalAllowAlways,
        kApprovalAllowOnce,
        kApprovalDeny,
        kApprovalTrustFolder,
        kPlanApprove,
        kPlanReject,
        kTuiDecisionTimeout;
export 'src/tui/tui_permission_prompt.dart';
export 'src/tui/tui_permission_view.dart';
export 'src/tui/tui_plan.dart';
export 'src/tui/tui_plan_view.dart';
export 'src/tui/tui_provider.dart';
export 'src/tui/tui_provider_view.dart';
export 'src/tui/tui_session_picker.dart';
export 'src/tui/tui_session_picker_view.dart';
export 'src/tui/tui_shell_mode.dart'
    show TuiShellMode, shellInputPlaceholder, shellStatusHint;
export 'src/tui/tui_skill_command.dart';
export 'src/tui/tui_status_info.dart';
export 'src/tui/tui_views.dart';
export 'src/tui/voice_reporter.dart';

/// conatus_code：基于 conatus 运行时的终端编码智能体。
///
/// 原 `conatus_tui` / `conatus_fs_tools` / `conatus_coding` 三个包已合并进本包，
/// 各自保留独立入口：[tui.dart] / [fs_tools.dart] / [coding.dart]。本文件是
/// conatus_code 自身新增能力的入口（配置、沙箱、新增工具）。
library;

export 'src/assembly/permission_mode.dart' show toTuiPermissionMode;
export 'src/autonomous/autonomous_assembly.dart' show provideAutonomous;
export 'src/background/background_tasks.dart'
    show
        BackgroundException,
        BackgroundTask,
        BackgroundTaskService,
        BackgroundTaskView;
export 'src/background/background_tools.dart'
    show
        BackgroundKillTool,
        BackgroundOutputTool,
        ListBackgroundTasksTool,
        RunCommandBackgroundTool,
        kBackgroundOutputLimit,
        provideBackgroundTools;
export 'src/budget/budgeted_llm.dart'
    show BudgetedLlmProvider, kBudgetExhaustedReply, provideBudgetedLlm;
export 'src/budget/cost_tracker.dart' show CostTrackerImpl, TokenUsage;
export 'src/budget/turn_budget.dart' show TurnBudget;
export 'src/checkpoint/checkpoint_archive.dart'
    show
        CheckpointArchiveEntry,
        CheckpointArchiveWriter,
        checkpointArchiveName,
        readCheckpointArchive,
        readCheckpointEntries,
        readCheckpointManifest,
        writeCheckpointArchive;
export 'src/checkpoint/checkpoint_backend.dart' show openCheckpointStore;
export 'src/checkpoint/checkpoint_hashes.dart'
    show
        checkpointHashesFile,
        deleteCheckpointHashes,
        readCheckpointHashes,
        writeCheckpointHashes;
export 'src/checkpoint/checkpoint_manager.dart' show CheckpointManager;
export 'src/checkpoint/checkpoint_paths.dart'
    show
        checkpointExcluded,
        checkpointRelativeTo,
        kCheckpointDefaultIgnores,
        kCheckpointVcsDir;
export 'src/checkpoint/checkpoint_restore.dart' show restoreArchiveCheckpoint;
export 'src/checkpoint/checkpoint_scan.dart'
    show checkpointIncluded, checkpointWalk;
export 'src/checkpoint/checkpoint_store.dart' show CheckpointStore;
export 'src/checkpoint/checkpoint_store_archive.dart'
    show ArchiveCheckpointStore;
export 'src/checkpoint/checkpoint_store_git.dart' show GitShadowStore;
export 'src/checkpoint/checkpoint_types.dart'
    show
        CheckpointException,
        CheckpointFileEntry,
        CheckpointInfo,
        CheckpointManifest,
        CheckpointRestore,
        CheckpointRewindResult;
export 'src/checkpoint/global_git_ignore.dart' show resolveGlobalGitIgnore;
export 'src/checkpoint/shadow_git_runner.dart'
    show GitResult, GitRunner, ProcessGitRunner, UnavailableGitRunner;
export 'src/config/config_credentials.dart' show ConfigCredentials;
export 'src/config/config_loader.dart' show ConfigException, loadConfig;
export 'src/config/config_path.dart'
    show
        kConfigDirName,
        kConfigFileName,
        kConfigHomeEnv,
        resolveConfigDir,
        resolveConfigPath;
export 'src/config/config_schema.dart'
    show
        CheckpointBackend,
        AgentConfig,
        ApprovalConfig,
        ApprovalMode,
        BackgroundConfig,
        BudgetConfig,
        CheckpointConfig,
        ConatusCodeConfig,
        HooksConfig,
        LintConfig,
        LlmConfig,
        LoopControlConfig,
        McpConfig,
        McpServerSpec,
        McpServerType,
        ModelConfig,
        ProviderConfig,
        ProviderType,
        RetrySettings,
        SandboxPreset,
        SandboxSettings,
        ServiceConfig,
        ThinkingConfig;
export 'src/config/config_writer.dart'
    show
        ModelEntry,
        appendModelSection,
        appendProviderSection,
        appendProviderToFile,
        deriveProviderName,
        upsertDefaultModel,
        writeConfigFile;
export 'src/config/project_data_dir.dart' show resolveProjectDataDir;
export 'src/diagnose/doctor.dart' show DoctorCheck, doctorChecks;
export 'src/diff/diff_parse.dart' show parseUnifiedDiff;
export 'src/diff/diff_types.dart' show DiffFile, DiffHunk, DiffOp, DiffOpKind;
export 'src/diff/preview.dart' show buildApprovalPreview, kPreviewMaxChars;
export 'src/diff/unified_diff.dart'
    show buildUnifiedDiff, kMaxDiffLines, splitLines;
export 'src/fs_tools/spill_dir.dart'
    show kNavaProjectDirName, toolResultSpillDir;
export 'src/headless/headless_runner.dart'
    show HeadlessFormat, HeadlessResult, renderHeadless, runHeadless;
export 'src/hooks/hooks.dart' show HookResult, Hooks, provideHooks, runHooks;
export 'src/lint/dart_machine.dart'
    show
        DartDiagnostic,
        formatDartDiagnostics,
        kDartMachineFields,
        kLintMaxPerFile,
        parseDartMachine;
export 'src/lint/lint_probe.dart'
    show LintOutputFormat, LintProbe, detectLintProbe;
export 'src/lint/linter.dart'
    show
        LinterService,
        provideLinter,
        kLintFeedbackChars,
        kLintMaxTargets,
        kLintToolNames;
export 'src/mcp/mcp_assembly.dart'
    show attachMcpServers, toMcpServerConfig, toMcpTransport;
export 'src/sandbox/command_policy.dart'
    show
        CommandDecision,
        CommandPolicy,
        CommandVerdict,
        resolveAllowedExecutables,
        resolveReadAllowedPaths;
export 'src/sandbox/jailed_file_system.dart' show JailedFileSystem;
export 'src/sandbox/rejecting_shell.dart'
    show RejectingShellExecutor, kSandboxUnavailable;
export 'src/sandbox/sandbox_assembly.dart'
    show SandboxLayers, resolveSandboxLayers;
export 'src/sandbox/sandbox_probe.dart'
    show SandboxBackend, SandboxException, probeSandboxBackend;
export 'src/sandbox/sandboxed_shell.dart'
    show SandboxedShellExecutor, SandboxReviewPrompter;
export 'src/sandbox/sandboxed_shell_options.dart' show SandboxedShellOptions;
export 'src/sandbox/seatbelt_profile.dart'
    show
        buildSandboxParams,
        buildSeatbeltProfile,
        defaultWritableCaches,
        seatbeltMachAllowlist;
export 'src/subagent/subagent_progress.dart'
    show SubAgentLine, SubAgentProgressStore;
export 'src/subagent/swarm_member.dart'
    show SwarmMember, SwarmProjection, SwarmSink;
export 'src/tools/apply_patch.dart' show ApplyPatchTool;
export 'src/tools/code_tools.dart' show provideCodeTools;
export 'src/tools/git_tools.dart'
    show GitCommitTool, GitDiffTool, GitRun, GitStatusTool, gitQuote, runGit;
export 'src/tools/git_write_tools.dart'
    show GitAddTool, GitBranchTool, GitStashTool;
export 'src/tools/list_files.dart' show ListFilesTool;
export 'src/tools/run_command.dart' show RunCommandTool;
export 'src/tools/run_tests.dart' show RunTestsTool;
export 'src/tools/update_plan.dart' show UpdatePlanTool, provideUpdatePlanTool;
export 'src/tui/project_context.dart'
    show kProjectContextMaxChars, loadProjectContext;
export 'src/tui/recent_session.dart' show findRecentSessionId;
export 'src/version.dart' show navaVersion;

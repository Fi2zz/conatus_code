/// conatus_code：基于 conatus 运行时的终端编码智能体。
///
/// 原 `conatus_tui` / `conatus_fs_tools` / `conatus_coding` 三个包已合并进本包，
/// 各自保留独立入口：[tui.dart] / [fs_tools.dart] / [coding.dart]。本文件是
/// conatus_code 自身新增能力的入口（配置、沙箱、新增工具）。
library;

export 'package:conatus_checkpoint/conatus_checkpoint.dart'
    show
        ArchiveCheckpointStore,
        CheckpointArchiveEntry,
        CheckpointArchiveWriter,
        CheckpointException,
        CheckpointFileChange,
        CheckpointFileEntry,
        CheckpointInfo,
        CheckpointManager,
        CheckpointManifest,
        CheckpointOptions,
        CheckpointPolicy,
        CheckpointRestore,
        CheckpointRewindResult,
        CheckpointStore,
        DiffSource,
        GitResult,
        GitRunner,
        GitShadowStore,
        ProcessGitRunner,
        UnavailableGitRunner,
        WorkingDiff,
        checkpointArchiveName,
        checkpointExcluded,
        checkpointHashesFile,
        checkpointIncluded,
        checkpointRelativeTo,
        checkpointWalk,
        deleteCheckpointHashes,
        kCheckpointArchiveTempSuffix,
        kCheckpointDefaultIgnores,
        kCheckpointVcsDir,
        kDiffNoTurnNotice,
        openCheckpointStore,
        readCheckpointArchive,
        readCheckpointEntries,
        readCheckpointManifest,
        readCheckpointHashes,
        resolveGlobalGitIgnore,
        restoreArchiveCheckpoint,
        writeCheckpointArchive,
        writeCheckpointHashes;
export 'package:conatus_checkpoint/revert.dart'
    show RedoResult, RevertException, RevertService, RevertStage, UndoResult;
export 'package:conatus_diff/conatus_diff.dart'
    show
        DiffFile,
        DiffHunk,
        DiffOp,
        DiffOpKind,
        DiffScope,
        FileDiff,
        PatchContextException,
        applyDiffFile,
        applyEditText,
        buildUnifiedDiff,
        kMaxDiffLines,
        parseUnifiedDiff,
        splitLines;
export 'package:conatus_fs_tools/conatus_fs_tools.dart'
    show ApplyPatchTool, ListFilesTool, buildApprovalPreview, kPreviewMaxChars;
export 'src/agents/agent_builtins.dart' show kBuiltinAgents;
export 'src/agents/agent_definition.dart' show AgentDefinition, AgentMode;
export 'src/agents/agent_parser.dart'
    show AgentParseResult, parseAgentDocument, parseAgentDocumentDetailed;
export 'src/agents/agent_picker.dart' show AgentPicker;
export 'src/agents/agent_registry.dart' show AgentRegistry;
export 'src/agents/agent_resolver.dart' show AgentProfileResolver;
export 'src/assembly/permission_mode.dart' show toTuiPermissionMode;
export 'src/autonomous/autonomous_assembly.dart' show provideAutonomous;
export 'src/background/background_tasks.dart'
    show
        BackgroundException,
        BackgroundTask,
        BackgroundTaskService,
        BackgroundTaskView,
        backgroundOutputTail,
        kBackgroundOutputLimit;
export 'src/background/background_tools.dart'
    show
        BackgroundKillTool,
        BackgroundOutputTool,
        ListBackgroundTasksTool,
        RunCommandBackgroundTool,
        provideBackgroundTools;
export 'src/budget/budgeted_llm.dart'
    show BudgetedLlmProvider, kBudgetExhaustedReply, provideBudgetedLlm;
export 'src/budget/cost_tracker.dart' show CostTrackerImpl, TokenUsage;
export 'src/budget/turn_budget.dart' show TurnBudget;
export 'src/cli/harness_command.dart' show kHarnessUsage, runHarnessCommand;
export 'src/cli/import_command.dart' show kImportUsage, runImportCli;
export 'src/cli/jsonc.dart' show decodeJsonc, stripJsonc;
export 'src/cli/opencode_import_files.dart'
    show
        DefinitionFilePlan,
        ImportedDefinitionFile,
        planOpenCodeDefinitionFiles;
export 'src/cli/opencode_import_map.dart' show buildOpenCodeImport;
export 'src/cli/opencode_import_plan.dart'
    show OpenCodeImportPlan, planOpenCodeImport;
export 'src/cli/opencode_import_source.dart'
    show OpenCodeDocument, OpenCodeSources, loadOpenCodeSources;
export 'src/cli/opencode_import_types.dart'
    show
        ImportedAgent,
        ImportedCommand,
        ImportedModel,
        ImportedPermission,
        ImportedProvider,
        ImportedReference,
        OpenCodeImport;
export 'src/commands/command_definition.dart' show CommandDefinition;
export 'src/commands/command_dispatcher.dart' show CommandDispatcher;
export 'src/commands/command_expander.dart'
    show expandCommand, kCommandShellOutputLimit, tokenizeCommandArguments;
export 'src/commands/command_parser.dart'
    show CommandParseResult, parseCommandDocument, parseCommandDocumentDetailed;
export 'src/commands/command_registry.dart' show CommandRegistry;
export 'src/config/config_credentials.dart' show ConfigCredentials;
export 'src/config/config_loader.dart' show ConfigException, loadConfig;
export 'src/config/config_path.dart'
    show
        kConfigDirName,
        kConfigFileName,
        kConfigHomeEnv,
        resolveConfigDir,
        resolveOAuthTokenDir,
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
        CustomToolConfig,
        FormatterConfig,
        HooksConfig,
        LintConfig,
        LlmConfig,
        LspConfig,
        LspServerConfig,
        McpConfig,
        McpServerSpec,
        McpServerType,
        ModelConfig,
        PermissionConfig,
        ProviderConfig,
        ProviderType,
        ReferenceConfig,
        RetrySettings,
        StoryConfig,
        TuiConfig,
        XerjConfig;
export 'src/config/config_writer.dart'
    show
        ModelEntry,
        appendMcpServerSection,
        appendModelSection,
        appendProviderSection,
        appendProviderToFile,
        deriveProviderName,
        upsertDefaultModel,
        writeConfigFile,
        writeFileAtomic;
export 'src/config/mcp_json.dart'
    show
        loadClaudeDesktopMcpSpecs,
        loadEffectiveMcpServers,
        loadMcpJsonSpecs,
        mergeMcpServerSpecs;
export 'src/config/project_data_dir.dart'
    show defaultProjectDataDir, projectDirProtected, resolveProjectDataDir;
export 'src/diagnose/doctor.dart' show DoctorCheck, doctorChecks;
export 'src/format/formatter_path.dart'
    show formatterExtension, resolveFormatterTarget;
export 'src/format/formatter_probe.dart' show FormatterProbe, detectFormatter;
export 'src/format/formatter_service.dart'
    show
        FormatterService,
        kFormatterMaxFiles,
        kFormatterReasonChars,
        kFormatterToolNames,
        provideFormatter;
export 'src/headless/headless_guard.dart'
    show approvalModeIgnoredNotice, headlessAskNotice;
export 'src/headless/headless_runner.dart'
    show HeadlessFormat, HeadlessResult, renderHeadless, runHeadless;
export 'src/hooks/hooks.dart' show HookResult, Hooks, provideHooks, runHooks;
export 'src/instructions/instruction_loader.dart' show InstructionLoader;
export 'src/instructions/instruction_project.dart' show kInstructionFileNames;
export 'src/instructions/instruction_prompt.dart' show InstructionPrompt;
export 'src/instructions/instruction_source.dart'
    show
        InstructionDoc,
        InstructionTarget,
        capInstructionText,
        expandInstructionHome,
        isWithinWorkdir,
        joinInstructionDocs,
        joinInstructionPath,
        kInstructionMaxChars,
        kInstructionTotalMaxChars,
        kInstructionTotalTruncated,
        kInstructionTruncated,
        kInstructionUrlTimeout,
        loadInstructionTargets,
        readInstructionFile,
        resolveInstructionTargets;
export 'src/instructions/instruction_wiring.dart'
    show
        instrumentInstructionNotes,
        instructionNotePath,
        kInstructionNoteTools,
        kInstructionsService,
        provideInstructionLoader;
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
export 'src/lsp/lsp_client.dart' show LspClient;
export 'src/lsp/lsp_manager.dart' show LspManager, LspServerStatus;
export 'src/lsp/lsp_navigation.dart'
    show LspDocumentSymbol, LspLocation, LspNavigator;
export 'src/lsp/lsp_navigation_tools.dart'
    show
        LspDefinitionTool,
        LspDocumentSymbolsTool,
        LspHoverTool,
        LspReferencesTool;
export 'src/lsp/lsp_tool.dart' show LspDiagnosticsTool, formatLspDiagnostics;
export 'src/lsp/lsp_types.dart'
    show LspDiagnostic, LspDiagnosticsSource, LspException, LspSeverity;
export 'src/mcp/mcp_assembly.dart'
    show attachMcpServers, toMcpServerConfig, toMcpTransport;
export 'src/mcp/mcp_cli.dart' show McpCliDeps, runMcpCli;
export 'src/mcp/mcp_oauth_runtime.dart' show McpOAuthRuntime;
export 'src/mcp/mcp_prompt_commands.dart'
    show
        kMcpReservedServerName,
        loadMcpPromptCommands,
        registerMcpPromptCommands;
export 'src/permissions/permission_rule_pattern.dart'
    show kRememberedRuleSource, permissionRuleFor, permissionRulesFor;
export 'src/permissions/permission_wiring.dart' show PermissionWiring;
export 'src/project/project_cli.dart' show runProjectCli;
export 'src/project/project_database.dart'
    show ProjectDatabase, ProjectRecord, WorktreeRecord;
export 'src/project/project_identity.dart'
    show ProjectIdentity, normalizeRemote, resolveProjectIdentity;
export 'src/project/project_paths.dart'
    show workspaceDirName, workspaceSlug, workspacesRoot;
export 'src/project/project_registry.dart' show ProjectRegistry, WorkspaceInfo;
export 'src/project/project_repair.dart'
    show ProjectRepairReport, repairProjectRegistry;
export 'src/project/worktree_cli.dart' show runWorktreeCli;
export 'src/project/worktree_service.dart'
    show WorktreeCreateResult, WorktreeService;
export 'src/references/references.dart'
    show
        ResolvedReference,
        kReferenceSectionName,
        kReferenceSectionOrder,
        provideReferencePrompt,
        renderReferences,
        resolveReferences;
export 'src/story/story.dart' show StoryRecorder, kStoryToolNames, provideStory;
export 'src/story/story_blocks.dart'
    show
        blockBelongsTo,
        blocksOfFile,
        normalizeParagraphText,
        opTextOf,
        paragraphBlockId,
        pathOfBlock,
        renderFileText,
        splitParagraphs;
export 'src/story/story_commands.dart'
    show
        StoryDiscardResult,
        discardStoryPatch,
        renderStoryDiscard,
        renderStoryPreview;
export 'src/story/story_conflict.dart'
    show
        applyPendingOp,
        conflictClose,
        kConflictOpen,
        kConflictSplit,
        mergeConflictVersions,
        readPendingBases;
export 'src/story/story_notices.dart'
    show StoryNotices, StoryFileChange, diffLines, renderEditNotice;
export 'src/story/story_pending.dart'
    show StoryPending, bindStoryPending, renderStoryPending, tryCompileOps;
export 'src/story/story_render.dart'
    show renderStoryTimeline, storyEditedPaths, storyOpLabel, storyPatchTime;
export 'src/story/story_review.dart' show StoryReviewGate, previewEditedOps;
export 'src/story/story_scan.dart' show kStorySkipDirs, kStoryTextExtensions;
export 'src/story/story_sync.dart'
    show
        anchorForNewFile,
        buildSyncOps,
        kParagraphLimit,
        syncFileOps,
        wholeFileOps;
export 'src/story/story_watcher.dart' show StoryWatcher;
export 'src/subagent/subagent_progress.dart'
    show SubAgentLine, SubAgentProgressStore;
export 'src/subagent/swarm_member.dart'
    show SwarmMember, SwarmProjection, SwarmSink;
export 'src/tool_result_spill.dart'
    show kNavaProjectDirName, toolResultSpillDir;
export 'src/tools/code_tools.dart' show provideCodeTools;
export 'src/tools/command_policy.dart'
    show CommandDecision, CommandPolicy, CommandVerdict;
export 'src/tools/custom_tools.dart' show CustomTool, provideCustomTools;
export 'src/tools/git_tools.dart'
    show GitCommitTool, GitDiffTool, GitRun, GitStatusTool, gitQuote, runGit;
export 'src/tools/git_write_tools.dart'
    show GitAddTool, GitBranchTool, GitStashTool;
export 'src/tools/guarded_shell.dart'
    show
        CommandReviewPrompter,
        GuardedShellExecutor,
        RejectedShellProcess,
        rejectedRun;
export 'src/tools/protected_command.dart'
    show
        gitWriteViolation,
        kReadOnlyCommandCode,
        kReadOnlyCommandMessage,
        readOnlyCommandViolation;
export 'src/tools/run_command.dart' show RunCommandTool;
export 'src/tools/run_tests.dart' show RunTestsTool;
export 'src/tools/update_plan.dart' show UpdatePlanTool, provideUpdatePlanTool;
export 'src/tui/definition_watcher.dart' show DefinitionWatcher;
export 'src/tui/project_context.dart'
    show kProjectContextMaxChars, loadProjectContext;
export 'src/tui/recent_session.dart' show findRecentSessionId;
export 'src/version.dart' show navaVersion;

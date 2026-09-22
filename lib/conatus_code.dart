/// conatus_code：基于 conatus 运行时的终端编码智能体。
///
/// 原 `conatus_tui` / `conatus_fs_tools` / `conatus_coding` 三个包已合并进本包，
/// 各自保留独立入口：[tui.dart] / [fs_tools.dart] / [coding.dart]。本文件是
/// conatus_code 自身新增能力的入口（配置、沙箱、新增工具）。
library;

export 'src/assembly/permission_mode.dart' show toTuiPermissionMode;
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
        AgentConfig,
        ApprovalConfig,
        ApprovalMode,
        ConatusCodeConfig,
        LlmConfig,
        SandboxPreset,
        SandboxSettings;
export 'src/diff/diff_parse.dart' show parseUnifiedDiff;
export 'src/diff/diff_types.dart' show DiffFile, DiffHunk, DiffOp, DiffOpKind;
export 'src/diff/preview.dart' show buildApprovalPreview, kPreviewMaxChars;
export 'src/diff/unified_diff.dart'
    show buildUnifiedDiff, kMaxDiffLines, splitLines;
export 'src/tools/apply_patch.dart' show ApplyPatchTool;
export 'src/tools/code_tools.dart' show provideCodeTools;
export 'src/tools/git_tools.dart' show GitDiffTool, GitRun, GitStatusTool, runGit;
export 'src/tools/list_files.dart' show ListFilesTool;

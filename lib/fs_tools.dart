/// conatus 的文件系统工具包：read / write / edit / grep / glob。
///
/// **实验性**：API 可能在没有 major 版本变更的情况下调整，勿在生产环境依赖。
library;

export 'package:conatus_foundation/conatus_foundation.dart'
    show ReadOnlyPathGuard, normalizeReadOnlyPath;
export 'src/fs_tools/edit_file.dart' show EditFileTool;
export 'src/fs_tools/fs_tools.dart' show provideFsTools;
export 'src/fs_tools/glob_tool.dart' show GlobTool;
export 'src/fs_tools/read_file.dart' show ReadFileTool;
export 'src/fs_tools/ripgrep_binary.dart' show RipgrepBinary, RipgrepSource;
export 'src/fs_tools/ripgrep_tool.dart' show RipgrepTool;
export 'src/fs_tools/spill_dir.dart'
    show kNavaProjectDirName, toolResultSpillDir;
export 'src/fs_tools/write_file.dart' show WriteFileTool, WriteMode;
export 'src/read_only_policy.dart'
    show
        defaultReadOnlyRoots,
        kGlobalOpenCodePath,
        kOpenCodeDirName,
        kReadOnlyPathCode,
        kReadOnlyPathMessage,
        readOnlyRelativePath,
        readOnlyWritePath;

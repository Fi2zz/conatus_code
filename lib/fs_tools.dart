/// conatus_code 的兼容入口：文件工具已迁到 conatus_fs_tools。
library;

export 'package:conatus_foundation/conatus_foundation.dart'
    show ReadOnlyPathGuard, normalizeReadOnlyPath;
export 'package:conatus_fs_tools/conatus_fs_tools.dart';
export 'src/read_only_policy.dart'
    show
        defaultReadOnlyRoots,
        kGlobalOpenCodePath,
        kOpenCodeDirName,
        kReadOnlyPathCode,
        kReadOnlyPathMessage,
        readOnlyRelativePath,
        readOnlyWritePath;
export 'src/tool_result_spill.dart'
    show kNavaProjectDirName, toolResultSpillDir;

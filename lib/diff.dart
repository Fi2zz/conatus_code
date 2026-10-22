/// `/diff` 数据层入口：文件级差异模型、统一 diff 解析与检查点 / 工作区数据源。
///
/// 与伞包入口分开是因为 `diffLines` 与故事通报里的同名计数函数签名不同。
library;

export 'src/diff/diff_model.dart' show DiffScope, FileDiff;
export 'src/diff/diff_parser.dart' show diffLines, parseUnifiedDiff;
export 'src/diff/diff_source.dart' show DiffSource;
export 'src/diff/diff_types.dart' show DiffFile, DiffHunk;

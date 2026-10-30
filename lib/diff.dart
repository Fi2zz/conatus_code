/// `/diff` 数据层入口：公共 diff 类型来自 conatus_diff，数据源来自
/// conatus_checkpoint。
///
/// 与伞包入口分开是因为 `diffLines` 与故事通报里的同名计数函数签名不同。
library;

export 'package:conatus_checkpoint/conatus_checkpoint.dart'
    show DiffSource, kDiffNoTurnNotice, WorkingDiff;
export 'package:conatus_diff/conatus_diff.dart';

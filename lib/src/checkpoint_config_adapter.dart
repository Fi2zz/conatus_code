/// 产品检查点配置到检查点内核选项的适配。
///
/// 检查点内核只认 [checkpoint.CheckpointPolicy]；nava 的 `.opencode` 只读约定
/// 与项目数据目录排除面留在产品侧，由这里显式注入。
library;

import 'package:conatus_checkpoint/conatus_checkpoint.dart' as checkpoint;

import 'config/config_schema.dart';

/// 整树排除的产品目录：应用数据目录 / 用户 OpenCode 安装目录。
const List<String> kCheckpointExcludedPrefixes = <String>[
  '.opencode',
  '.config/opencode',
];

/// 只读的产品目录：既不进快照，也不被恢复写回或删除。
const List<String> kCheckpointReadOnlyPrefixes = <String>[
  '.opencode',
  '.config/opencode',
];

/// 不带用户扩展忽略项的产品策略（`tool/play.dart` 等直接走内核的场景用）。
const checkpoint.CheckpointPolicy kCheckpointPolicy =
    checkpoint.CheckpointPolicy(
      excludedPrefixes: kCheckpointExcludedPrefixes,
      readOnlyPrefixes: kCheckpointReadOnlyPrefixes,
    );

/// 把 `[checkpoint]` 配置映射成检查点内核选项。
checkpoint.CheckpointOptions checkpointOptions(CheckpointConfig config) {
  return checkpoint.CheckpointOptions(
    enabled: config.enabled,
    keep: config.keep,
    backend: checkpoint.CheckpointBackend.values.byName(config.backend.name),
    policy: checkpoint.CheckpointPolicy(
      ignore: config.ignore,
      excludedPrefixes: kCheckpointExcludedPrefixes,
      readOnlyPrefixes: kCheckpointReadOnlyPrefixes,
    ),
  );
}

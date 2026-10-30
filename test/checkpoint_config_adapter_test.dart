/// `[checkpoint]` 配置到检查点内核选项的映射。
library;

import 'package:conatus_checkpoint/conatus_checkpoint.dart' as checkpoint;
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/src/checkpoint_config_adapter.dart';
import 'package:test/test.dart';

void main() {
  test('保留 enabled / keep / backend', () {
    final CheckpointOptions options = checkpointOptions(
      const CheckpointConfig(
        enabled: false,
        keep: 7,
        backend: CheckpointBackend.archive,
      ),
    );
    expect(options.enabled, isFalse);
    expect(options.keep, 7);
    expect(options.backend, checkpoint.CheckpointBackend.archive);
  });

  test('三个后端字面量逐一映射', () {
    for (final CheckpointBackend backend in CheckpointBackend.values) {
      final CheckpointOptions options = checkpointOptions(
        CheckpointConfig(backend: backend),
      );
      expect(options.backend.name, backend.name);
    }
  });

  test('.opencode 与 .config/opencode 都是产品只读前缀', () {
    final CheckpointOptions options = checkpointOptions(
      const CheckpointConfig(),
    );
    expect(
      options.policy.readOnlyPrefixes,
      containsAll(<String>['.opencode', '.config/opencode']),
    );
    expect(
      options.policy.excludedPrefixes,
      containsAll(<String>['.opencode', '.config/opencode']),
    );
  });

  test('ignore 来自配置，不覆盖产品策略', () {
    final CheckpointOptions options = checkpointOptions(
      const CheckpointConfig(ignore: <String>['dist', 'generated']),
    );
    expect(options.policy.ignore, <String>['dist', 'generated']);
    expect(options.policy.readOnlyPrefixes, contains('.opencode'));
  });
}

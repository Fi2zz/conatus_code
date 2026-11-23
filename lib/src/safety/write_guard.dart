/// 读后写守卫：覆盖已有文件前必须在本会话读过，且读后文件未被改动。
///
/// 守卫是同步的（`ToolGuard`），所以只能做「检查」：不自动注入
/// `expected_version`。检查与真正写入之间存在毫秒级窗口，模型显式传
/// `expected_version` 时仍由工具自身的版本守卫兜底。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import '../paths/canonical_path.dart';
import 'patch_paths.dart';
import 'read_ledger.dart';

/// 未先读取就覆盖已有文件。
const String kWriteWithoutReadCode = 'WRITE_WITHOUT_READ';

/// 读后文件已被外部修改。
const String kWriteStaleReadCode = 'WRITE_STALE_READ';

/// 读后写守卫。
class ReadBeforeWriteGuard {
  ReadBeforeWriteGuard({
    required this.ledger,
    required this.workdir,
    this.home,
    this.toolNames = const <String>{'write', 'edit', 'apply_patch'},
  });

  /// 读台账。
  final ReadLedger ledger;

  /// 相对路径的解析基准。
  final String workdir;

  /// 家目录（`~` 展开）。
  final String? home;

  /// 受守卫约束的工具名。
  final Set<String> toolNames;

  /// 返回拒绝理由；`null` 表示放行。
  String? check(ToolCall call) {
    if (!toolNames.contains(call.name)) return null;
    final List<PatchTarget> targets = call.name == 'apply_patch'
        ? _patchTargets(call)
        : _pathTargets(call);
    for (final PatchTarget target in targets) {
      final String? denial = _checkTarget(target);
      if (denial != null) return denial;
    }
    return null;
  }

  String? _checkTarget(PatchTarget target) {
    final String? canonical = canonicalToolPath(workdir, home, target.path);
    if (canonical == null) return null;
    final String? current = fileFingerprint(canonical);
    if (current == null) return null; // 真正的新建文件，无需先读
    // `creates` 只是补丁文本的声明：声称新建但文件已存在时仍按覆盖检查，
    // 否则模型「以为文件不存在」的误判会直接改坏未读文件。
    final String? recorded = ledger.fingerprintOf(canonical);
    if (recorded == null) {
      return '$kWriteWithoutReadCode: 覆盖已有文件前必须先读取：'
          '${target.path}（请先调用 read）';
    }
    if (recorded != current) {
      return '$kWriteStaleReadCode: 文件自上次读取后已被修改：'
          '${target.path}（请重新 read）';
    }
    return null;
  }

  List<PatchTarget> _patchTargets(ToolCall call) {
    final Object? patch = call.arguments['patch'];
    return patch is String ? patchTargets(patch) : const <PatchTarget>[];
  }

  List<PatchTarget> _pathTargets(ToolCall call) {
    final Object? path = call.arguments['path'];
    return path is String
        ? <PatchTarget>[PatchTarget(path: path)]
        : const <PatchTarget>[];
  }
}

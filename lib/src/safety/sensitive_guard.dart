/// 敏感文件守卫：在工具执行前硬拒私钥/凭据与 `.env` 写入。
///
/// 只覆盖工具参数里的字面路径（含 `bash` 命令 token 与补丁目标）；变量拼接、
/// `sh -c "$CMD"` 等仍可绕过，属于已知盲区，不当作安全边界。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import '../paths/canonical_path.dart';
import 'patch_paths.dart';
import 'sensitive_paths.dart';

const Set<String> _writeTools = <String>{'write', 'edit', 'apply_patch'};

final RegExp _tokenSeparators = RegExp(r'''[\s"'`|&;<>()]+''');

final RegExp _writeOperators = RegExp(
  r'(>>?|\btee\b|\bsed\s+-i|\brm\b|\bmv\b|\bcp\b|\btruncate\b|\btouch\b|\bdd\b)',
);

/// 只把「看起来像路径」的 token 当候选：普通单词（`credentials`、
/// `id_rsa`）出现在提交信息或搜索词里时不能误伤。
bool _looksPathLike(String token) =>
    token.contains('/') ||
    token.contains('\\') ||
    token.startsWith('~') ||
    token.startsWith('.');

/// 敏感文件守卫。
// REASON: 装配入口需要一次性收齐四个开关与三个路径上下文，拆对象只会多一层转发。
class SensitivePathGuard {
  SensitivePathGuard({
    required this.tools,
    required this.workdir,
    this.home,
    this.protectPrivateKeys = true,
    this.denyDotenvWrites = true,
    this.extraPaths = const <String>{},
  });

  /// 工具注册表（读取 `pathParams`）。
  final ToolRegistry tools;

  /// 相对路径的解析基准。
  final String workdir;

  /// 家目录（`~` 展开）。
  final String? home;

  /// 是否硬拒私钥/凭据/追加路径。
  final bool protectPrivateKeys;

  /// 是否硬拒 `.env` 族写入。
  final bool denyDotenvWrites;

  /// 追加的敏感路径。
  final Set<String> extraPaths;

  /// 返回拒绝理由；`null` 表示放行。
  String? check(ToolCall call) {
    if (!protectPrivateKeys && !denyDotenvWrites && extraPaths.isEmpty) {
      return null;
    }
    for (final String candidate in _candidates(call)) {
      final String probe =
          canonicalToolPath(workdir, home, candidate, expandHome: false) ??
          candidate;
      final SensitiveMatch? match = matchSensitivePath(
        probe,
        extraPaths: extraPaths,
      );
      if (match == null) continue;
      if (!_denied(match.kind, call)) continue;
      return sensitiveMessage(match);
    }
    return null;
  }

  bool _denied(SensitiveKind kind, ToolCall call) {
    if (kind == SensitiveKind.dotenv) {
      if (call.name == 'bash') {
        return denyDotenvWrites && _looksWriteCommand(call);
      }
      return denyDotenvWrites && _writeTools.contains(call.name);
    }
    return protectPrivateKeys;
  }

  bool _looksWriteCommand(ToolCall call) {
    final Object? command = call.arguments['command'];
    return command is String && _writeOperators.hasMatch(command);
  }

  List<String> _candidates(ToolCall call) {
    final Set<String> found = <String>{};
    final Tool? tool = tools.get(call.name);
    final List<String> params = tool == null || tool.pathParams.isEmpty
        ? const <String>['path', 'file', 'dir', 'cwd', 'directory']
        : tool.pathParams;
    for (final String param in params) {
      final Object? value = call.arguments[param];
      if (value is String) found.add(value);
    }
    if (call.name == 'bash') {
      final Object? command = call.arguments['command'];
      if (command is String) {
        found.addAll(command.split(_tokenSeparators).where(_looksPathLike));
      }
    }
    if (call.name == 'apply_patch') {
      final Object? patch = call.arguments['patch'];
      if (patch is String) {
        found.addAll(patchTargets(patch).map((PatchTarget t) => t.path));
      }
    }
    return found.toList(growable: false);
  }
}

/// 读台账：记录「本会话读过哪个文件、读的是哪个版本」，并维护写后刷新。
///
/// 守卫是同步的（`ToolGuard`），所以指纹用 `FileStat.statSync` 计算；中间件
/// 在 `read` 成功后登记、在写成功后刷新，异常一律吞掉，绝不影响工具结果。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import '../paths/canonical_path.dart';
import 'patch_paths.dart';

/// 文件指纹：`changed:modified:size`；缺失或不可读返回 `null`。
String? fileFingerprint(String canonicalPath) {
  try {
    final FileStat info = FileStat.statSync(canonicalPath);
    if (info.type == FileSystemEntityType.notFound) return null;
    return '${info.changed.microsecondsSinceEpoch}:'
        '${info.modified.microsecondsSinceEpoch}:${info.size}';
  } on FileSystemException {
    return null;
  }
}

/// canonical 绝对路径 → 读取时的文件指纹。
class ReadLedger {
  final Map<String, String> _fingerprints = <String, String>{};

  /// 已登记的文件数。
  int get length => _fingerprints.length;

  /// 取登记指纹；没读过返回 `null`。
  String? fingerprintOf(String canonicalPath) => _fingerprints[canonicalPath];

  /// 登记/覆盖一条读取记录。
  void note(String canonicalPath, String fingerprint) {
    _fingerprints[canonicalPath] = fingerprint;
  }

  /// 删除一条记录（文件被删除或写后无法 stat）。
  void forget(String canonicalPath) => _fingerprints.remove(canonicalPath);

  /// 清空（会话切换）。
  void clear() => _fingerprints.clear();
}

/// 后置中间件：`read` 成功登记，`write`/`edit`/`apply_patch` 成功刷新。
class ReadLedgerMiddleware {
  ReadLedgerMiddleware({
    required this.ledger,
    required this.workdir,
    this.home,
  });

  /// 目标台账。
  final ReadLedger ledger;

  /// 相对路径的解析基准。
  final String workdir;

  /// 家目录（`~` 展开）。
  final String? home;

  /// 中间件入口。
  Future<ToolResult> call(
    ToolCall call,
    Future<ToolResult> Function() next,
  ) async {
    final ToolResult result = await next();
    if (result.isError) return result;
    try {
      switch (call.name) {
        case 'read':
          _recordRead(result);
        case 'write' || 'edit':
          _refreshCall(call);
        case 'apply_patch':
          _refreshPatch(call);
      }
    } on Object {
      // 台账是增强项：任何异常都不改变工具结果。
    }
    return result;
  }

  void _recordRead(ToolResult result) {
    final Object? value = result.value;
    if (value is! Map) return;
    final Object? path = value['path'];
    final Object? version = value['version'];
    if (path is! String || version is! String) return;
    final String? canonical = canonicalToolPath(
      workdir,
      home,
      path,
      expandHome: false,
    );
    if (canonical == null) return;
    // 用 read 返回的 version（与 fs 的指纹同一元组），而不是事后重新 stat：
    // 读与 stat 之间文件变化时，后者会把新指纹当成「模型看过的版本」。
    ledger.note(canonical, version);
  }

  void _refreshPatch(ToolCall call) {
    final Object? patch = call.arguments['patch'];
    if (patch is! String) return;
    for (final PatchTarget target in patchTargets(patch)) {
      _refresh(target.path);
    }
  }

  void _refreshCall(ToolCall call) {
    // append 只写增量，模型没看过原内容；不能因此授权后续整文件覆盖。
    if (call.name == 'write' && call.arguments['mode'] == 'append') return;
    _refresh(_pathArgument(call));
  }

  void _refresh(String? rawPath) {
    if (rawPath == null) return;
    final String? canonical = canonicalToolPath(
      workdir,
      home,
      rawPath,
      expandHome: false,
    );
    if (canonical == null) return;
    final String? fingerprint = fileFingerprint(canonical);
    if (fingerprint == null) {
      ledger.forget(canonical);
    } else {
      ledger.note(canonical, fingerprint);
    }
  }

  String? _pathArgument(ToolCall call) {
    final Object? path = call.arguments['path'];
    return path is String ? path : null;
  }
}

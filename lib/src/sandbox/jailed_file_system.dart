/// 沙箱化文件系统：把 conatus 的 [FileSystem] 接到 dart_io_sandbox 的 jail。
///
/// 路径解析走原始 [LocalFileSystem]（targetKey 是真实绝对路径），读写经
/// [SandboxFileSystem.bound] 限在根内；越界/策略违规统一转
/// `FsErrorCode.sandboxDenied`。守卫与编辑语义对齐 `fs_local_ops.dart`。
library;

import 'dart:io' as io;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:file/file.dart' as f;

import 'jailed_file_system_ops.dart';

/// conatus [FileSystem] 的 jail 实现：读写都限在 [root] 内。
class JailedFileSystem implements FileSystem {
  JailedFileSystem({
    required String root,
    SandboxPolicy? policy,
    SandboxAccessHook? onAccess,
  })  : _root = io.Directory(root).resolveSymbolicLinksSync(),
        _policy = policy ?? const SandboxPolicy(),
        _onAccess = onAccess,
        _raw = LocalFileSystem(cwd: root);

  /// 规范化后的沙箱根（真实路径）。
  final String _root;
  final SandboxPolicy _policy;
  final SandboxAccessHook? _onAccess;

  /// 原始本地文件系统：路径解析与只读委托的基准。
  final FileSystem _raw;

  late final SandboxFileSystem _jail = SandboxFileSystem.bound(
    root: _root,
    policy: _policy,
    onAccess: _onAccess,
  );

  @override
  Future<FsTarget> resolve(String path, {String? cwd}) async {
    final FsTarget target = await _raw.resolve(path, cwd: cwd);
    checkWithinRoot(_root, target);
    return target;
  }

  @override
  Future<String> readText(FsTarget target) async {
    checkWithinRoot(_root, target);
    try {
      return await _jail.file(target.targetKey).readAsString();
    } on SandboxError catch (e) {
      throw FsError(FsErrorCode.sandboxDenied, e.toString());
    } on FormatException {
      throw FsError(FsErrorCode.notText,
          'invalid UTF-8: "${target.displayPath}"');
    } on io.FileSystemException catch (e) {
      throw mapFsException(e, target);
    }
  }

  @override
  Future<List<FsDirEntry>> listDir(FsTarget target) async {
    checkWithinRoot(_root, target);
    return listDirFor(_jail, _raw, target);
  }

  @override
  Future<FsWriteOutcome> writeText(
    FsTarget target,
    String content, {
    FsWriteIntent? expected,
  }) async {
    checkWithinRoot(_root, target);
    final FsInfo? info = await _raw.stat(target);
    final bool exists = info != null;
    checkWriteGuard(expected, exists ? info.version : null, target);
    final String? before = exists ? await readOrNull(this, target) : null;
    await _writeThrough(target, content, createParents: true);
    final FsInfo? after = await _raw.stat(target);
    return FsWriteOutcome(
      operation: exists ? FsWriteOperation.update : FsWriteOperation.create,
      version: after?.version ?? '',
      before: before,
      after: content,
    );
  }

  @override
  Future<FsEditOutcome> editText(
    FsTarget target,
    FsEditRequest edit, {
    String? expectedVersion,
  }) async {
    checkWithinRoot(_root, target);
    final FsInfo? info = await _raw.stat(target);
    guardEditVersion(info, expectedVersion, target);
    final String original = await readText(target);
    final String edited = applyEdit(original, edit, target);
    await _writeThrough(target, edited);
    final FsInfo? after = await _raw.stat(target);
    return FsEditOutcome(
      version: after?.version ?? '',
      before: original,
      after: edited,
    );
  }

  @override
  Future<void> remove(FsTarget target) async {
    checkWithinRoot(_root, target);
    try {
      final io.FileSystemEntityType type = _jail.typeSync(target.targetKey);
      if (type == io.FileSystemEntityType.notFound) return;
      if (type == io.FileSystemEntityType.directory) {
        await _jail.directory(target.targetKey).delete(recursive: true);
        return;
      }
      await _jail.file(target.targetKey).delete();
    } on SandboxError catch (e) {
      throw FsError(FsErrorCode.sandboxDenied, e.toString());
    } on io.FileSystemException catch (e) {
      throw mapFsException(e, target);
    }
  }

  @override
  Future<FsInfo?> stat(FsTarget target) async {
    checkWithinRoot(_root, target);
    return _raw.stat(target);
  }

  @override
  Future<FsPathInfo?> lstat(String path, {String? cwd}) async {
    final FsTarget target = await resolve(path, cwd: cwd);
    return _raw.lstat(target.targetKey);
  }

  @override
  String processPath(FsTarget target) => _raw.processPath(target);

  @override
  String fileUrl(FsTarget target) => _raw.fileUrl(target);

  @override
  bool contains(FsTarget parent, FsTarget child) => _raw.contains(parent, child);

  /// 沙箱内写回；[createParents] 时先建父目录。违规统一转 sandboxDenied。
  Future<void> _writeThrough(FsTarget target, String content,
      {bool createParents = false}) async {
    try {
      final f.File file = _jail.file(target.targetKey);
      if (createParents) await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
    } on SandboxError catch (e) {
      throw FsError(FsErrorCode.sandboxDenied, e.toString());
    } on io.FileSystemException catch (e) {
      throw mapFsException(e, target);
    }
  }
}

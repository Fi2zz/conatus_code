/// JailedFileSystem 的守卫、编辑与映射工具（内部实现，不对外导出）。
library;

import 'dart:io' as io;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:file/file.dart' as f;

/// targetKey 必须落在沙箱根内，否则拒绝（fail-closed）。
void checkWithinRoot(String root, FsTarget target) {
  if (!withinRoot(root, target.targetKey)) {
    throw FsError(FsErrorCode.sandboxDenied, '路径越界：${target.displayPath}');
  }
}

bool withinRoot(String root, String path) =>
    path == root || path.startsWith('$root/');

/// 写入守卫：版本不符 / 创建但已存在，对齐 `fs_local_ops.dart`。
void checkWriteGuard(
    FsWriteIntent? expected, String? version, FsTarget target) {
  if (expected is FsReplaceIfVersion) {
    if (version == null || version != expected.version) {
      throw FsError(FsErrorCode.staleVersion,
          'cannot write "${target.displayPath}": file changed since it was read');
    }
  } else if (expected is FsCreateIfAbsent && version != null) {
    throw FsError(FsErrorCode.notObserved,
        'cannot overwrite existing "${target.displayPath}" without reading it first');
  }
}

/// 编辑的版本守卫：文件缺失或版本不符即报陈旧。
void guardEditVersion(FsInfo? info, String? expectedVersion, FsTarget target) {
  if (info == null) {
    throw FsError(FsErrorCode.staleVersion,
        'cannot edit "${target.displayPath}": file changed since it was read');
  }
  if (expectedVersion != null && info.version != expectedVersion) {
    throw FsError(FsErrorCode.staleVersion,
        'cannot edit "${target.displayPath}": file changed since it was read');
  }
}

/// 字面替换；未找到 / 多处且非 replace_all 时报错，对齐编辑工具语义。
String applyEdit(String original, FsEditRequest edit, FsTarget target) {
  final int count =
      edit.oldString.isEmpty ? 0 : original.split(edit.oldString).length - 1;
  if (count == 0) {
    throw FsError(FsErrorCode.editNotFound,
        'old_string was not found in "${target.displayPath}"');
  }
  if (!edit.replaceAll && count > 1) {
    throw FsError(FsErrorCode.ambiguousEdit,
        'old_string matched $count times in "${target.displayPath}"');
  }
  return original.split(edit.oldString).join(edit.newString);
}

/// 把 dart:io 异常映射为 conatus 错误码（ENOENT=2、EISDIR=21）。
FsError mapFsException(io.FileSystemException e, FsTarget target) {
  final int? code = e.osError?.errorCode;
  if (code == 2) {
    return FsError(FsErrorCode.notFound,
        'cannot read "${target.displayPath}": not found');
  }
  if (code == 21) {
    return FsError(FsErrorCode.notRegularFile,
        'cannot read "${target.displayPath}": not a regular file');
  }
  return FsError(FsErrorCode.ioError, e.message);
}

/// 目录条目映射：类型经 stat 判定，子目标用原始 fs 解析。
Future<FsDirEntry> dirEntryFor(
    FileSystem raw, f.FileSystemEntity entity) async {
  final io.FileStat stat = entity.statSync();
  final FsTarget child = await raw.resolve(entity.path);
  return FsDirEntry(
    name: basenameOf(entity.path),
    type: typeOfFs(stat.type),
    target: child,
    size: stat.type == io.FileSystemEntityType.file ? stat.size : null,
  );
}

/// 读取失败时返回 null（审计 before 字段用）。
Future<String?> readOrNull(FileSystem fs, FsTarget target) async {
  try {
    return await fs.readText(target);
  } catch (_) {
    return null;
  }
}

/// 列出目录并映射条目；越界/策略违规转 sandboxDenied。
Future<List<FsDirEntry>> listDirFor(
    SandboxFileSystem jail, FileSystem raw, FsTarget target) async {
  final List<FsDirEntry> entries = <FsDirEntry>[];
  try {
    await for (final f.FileSystemEntity entity
        in jail.directory(target.targetKey).list()) {
      entries.add(await dirEntryFor(raw, entity));
    }
  } on SandboxError catch (e) {
    throw FsError(FsErrorCode.sandboxDenied, e.toString());
  } on io.FileSystemException catch (e) {
    throw mapFsException(e, target);
  }
  entries.sort((FsDirEntry a, FsDirEntry b) => a.name.compareTo(b.name));
  return entries;
}

String basenameOf(String path) {
  final int index = path.lastIndexOf(io.Platform.pathSeparator);
  return index < 0 ? path : path.substring(index + 1);
}

FsFileType typeOfFs(io.FileSystemEntityType type) => switch (type) {
      io.FileSystemEntityType.file => FsFileType.file,
      io.FileSystemEntityType.directory => FsFileType.directory,
      io.FileSystemEntityType.link => FsFileType.symlink,
      _ => FsFileType.other,
    };

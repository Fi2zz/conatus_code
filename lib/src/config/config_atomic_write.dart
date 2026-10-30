/// 配置文件与令牌文件的原子写入。
///
/// 先写同目录临时文件、收紧权限，再 `rename` 覆盖目标：任何时刻都不会出现
/// 半写的配置，也不会留下 `.tmp` 残余（失败同样清理）。
library;

import 'dart:io';

import '../read_only_policy.dart';

/// 0600（`rw-------`）的十进制值；Dart 没有八进制字面量。
const int kOwnerOnlyMode = 0x180;

/// 原子写入 [path]：父目录自动创建，临时文件与目标同目录。
///
/// 目标是符号链接（dotfiles 常见）时写穿到链接目标，**不切断链接**。
/// [mode] 缺省 0600——配置里可能含 API Key，同机其他用户不能读。
///
/// `.opencode` / `~/.config/opencode` 及其符号链接别名一律拒绝（在创建父
/// 目录之前判定，见 [readOnlyWritePath]）。
void writeFileAtomic(String path, String content, {int mode = kOwnerOnlyMode}) {
  if (readOnlyWritePath(path)) {
    throw FileSystemException(kReadOnlyPathMessage, path);
  }
  final File target = _writeTarget(path);
  target.parent.createSync(recursive: true);
  final File temp = File(
    '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    // 先建空文件并收权限，再写敏感内容：任何瞬间都不能出现 0644 的配置。
    temp.createSync();
    _restrict(temp, mode);
    temp.writeAsStringSync(content, flush: true);
    if (Platform.isWindows && target.existsSync()) target.deleteSync();
    temp.renameSync(target.path);
  } finally {
    if (temp.existsSync()) temp.deleteSync();
  }
}

/// 写配置（父目录自动创建）并收紧权限为 0600。
void writeConfigFile(String path, String content) {
  writeFileAtomic(path, content);
}

/// 符号链接解析到真实文件；普通路径原样返回。
File _writeTarget(String path) {
  if (!FileSystemEntity.isLinkSync(path)) return File(path);
  return File(File(path).resolveSymbolicLinksSync());
}

void _restrict(File file, int mode) {
  if (Platform.isWindows) return;
  final ProcessResult result = Process.runSync('chmod', <String>[
    (mode & 0x1FF).toRadixString(8),
    file.path,
  ]);
  if (result.exitCode != 0) {
    throw FileSystemException('无法设置文件权限', file.path);
  }
}

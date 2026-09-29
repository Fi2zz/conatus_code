/// 工具结果溢出目录的位置。
///
/// **必须在工作目录内**：溢出预览会告诉模型「调用 read_file 读取该路径」，而
/// `read_file` 走 Layer 1 的 fs jail（根 = 工作目录，`fs_jail` 默认开）。早前溢出
/// 文件落在 `systemTemp`，于是既写不出去（`FS_SANDBOX_DENIED`），就算写出去模型
/// 也读不回来——预览里那句话是假的。放在工作目录内两边都通。
///
/// 目录名以 `.` 开头并加入 `glob` / `list_files` 的跳过集，不污染目录列表。
library;

import 'dart:io';

/// nava 在工作目录内使用的目录名。
const String kNavaProjectDirName = '.nava';

/// 工具结果溢出目录：`<workdir>/.nava/tool-results`。
String toolResultSpillDir(String workdir) {
  final String sep = Platform.pathSeparator;
  return '$workdir$sep$kNavaProjectDirName${sep}tool-results';
}

/// 两种存储实现共用的工作区遍历：决定「哪些文件进快照」。
///
/// 单独成文件是为了让 [ArchiveCheckpointStore] 与 [GitShadowStore] 的排除
/// 判定**逐字节一致**。这不是洁癖：影子实现一度用 `git add --all`，git 会
/// 顺从工作区的 `.gitignore`（Swift 项目的 `.build/`、前端项目的
/// `dist/` 都在里面），而归档实现只认 [kCheckpointDefaultIgnores] + 用户
/// `ignore`。两者排除面不一致的后果是实打实的：影子快照只收了 293 个文件，
/// 而恢复按 rsync 语义删掉了其余 9119 个。
///
/// 结论：**排除判定必须由我们自己算，不能委托给 git**。影子实现改为把
/// 自己 walk 出来的路径显式喂给 `git add -f`（`-f` 覆盖 ignore 规则；既然
/// 只传我们想要的，结果就等于自定义排除面）。
library;

import 'dart:io';

import 'checkpoint_paths.dart';

/// 遍历 [root] 下需进快照的文件（排除目录树、跟随链接关闭）。
///
/// 跳过符号链接：恢复侧对等处理（`ensureRestorable` 做越界校验），快照侧
/// 不收，两边才对得上。
Stream<FileSystemEntity> checkpointWalk(
  String root,
  String projectRel,
  List<String> ignore,
) => Directory(root)
    .list(recursive: true, followLinks: false)
    .where(
      (FileSystemEntity e) => checkpointIncluded(e, root, projectRel, ignore),
    );

/// 单个实体是否进快照（是文件 + 未命中排除）。
bool checkpointIncluded(
  FileSystemEntity entity,
  String root,
  String projectRel,
  List<String> ignore,
) {
  if (entity is! File) return false;
  final String rel = checkpointRelativeTo(entity, root);
  return !checkpointExcluded(rel, projectRel, ignore);
}

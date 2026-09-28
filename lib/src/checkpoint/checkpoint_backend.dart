/// 按配置 + 环境选出检查点存储实现。
///
/// `auto`（缺省）：有 git 用影子仓库（对象复用、跨会话免全量），没有就退回
/// 自研归档（零外部依赖，任何环境可跑）。探测只做一次（`git --version`，
/// 5s 超时），代价可忽略。
///
/// `git` / `archive` 是显式选择，不做降级——用户写死就是想要那个行为
/// （`git` 在无 git 时让每轮快照报错，比悄悄换实现更容易察觉问题）。
library;

import '../config/config_schema.dart';
import 'checkpoint_store.dart';
import 'checkpoint_store_archive.dart';
import 'checkpoint_store_git.dart';
import 'shadow_git_runner.dart';

/// 造出配置指定的存储。
///
/// [root] 是工作区根，[projectDir] 是项目数据目录（影子仓库落在它下面）。
Future<CheckpointStore> openCheckpointStore({
  required CheckpointConfig config,
  required String root,
  required String projectDir,
  GitRunner? git,
}) async {
  final GitRunner runner = git ?? const ProcessGitRunner();
  final bool shadowWanted = switch (config.backend) {
    CheckpointBackend.git => true,
    CheckpointBackend.archive => false,
    CheckpointBackend.auto => await runner.available(),
  };
  if (shadowWanted) {
    return GitShadowStore(
      root: root,
      projectDir: projectDir,
      keep: config.keep,
      ignore: config.ignore,
      git: runner,
    );
  }
  return ArchiveCheckpointStore(
    root: root,
    projectDir: projectDir,
    keep: config.keep,
    ignore: config.ignore,
  );
}

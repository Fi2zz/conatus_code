/// 检查点存储的抽象接口：把「快照存到哪、怎么存」与检查点编排解耦。
///
/// 编排（轮次计数、串行链、基线/差量的时序、绑定解绑）在
/// `checkpoint_manager.dart`；存储（怎么把工作区状态落成可回滚的形态）在
/// 实现里。现有两种实现：
///
/// - [ArchiveCheckpointStore]：自研 gzip 归档（`checkpoint_store_archive.dart`）。
///   零外部依赖，任何环境可跑；代价是每轮要自己处理容器格式，且同一文件
///   的每个版本各存一份完整内容。
/// - 影子 git 仓库（`checkpoint_store_git.dart`）：把工作区提交进一个独立
///   的 git dir。内容寻址 + zlib + 增量全由 git 提供，跨会话复用对象。
///
/// 两种实现都必须满足的语义（`checkpoint_restore.dart` 依赖之）：
///
/// - 快照内容是工作区文件；`projectDir` 整树、`.git` 与 `ignore` 命中的
///   路径一律不进快照（见 `checkpoint_paths.dart`）。
/// - 恢复是 rsync 语义：目标态有的覆盖/补回，当前有而目标态没有的删除。
/// - 恢复前做符号链接越界校验（fail-closed），越界时一个文件都不动。
/// - 符号链接不进快照。
/// - 单轮快照失败不抛给调用方（编排层转成提示）。
library;

import 'checkpoint_types.dart';

/// 工作区快照存储。
///
/// 同步方法（[list] / [prune]）供 UI 展示与编排判定用，故不返回 Future；
/// 需要 I/O 的（[snapshot] / [clearSession] / [loadManifest] / [restore]）
/// 走异步。
abstract class CheckpointStore {
  /// 工作区根（绝对路径）。
  String get root;

  /// 项目数据目录（绝对路径）；连同其整树排除在快照外。
  String get projectDir;

  /// 回滚点数（含基线）；`<= 0` 不限制。
  int get keep;

  /// 额外忽略的相对路径前缀。
  List<String> get ignore;

  /// 快照当前工作区为 [turn] 轮。
  ///
  /// [lastEventId] 是快照时刻会话的最后一条事件 id（对话 fork 的切点），
  /// 随该轮一起持久化，恢复时回传给调用方。
  Future<void> snapshot(String sessionId, int turn, {String? lastEventId});

  /// 清空某会话的全部检查点。
  ///
  /// 重绑即新时间线：旧基线/差量一并移除，避免「新基线 + 旧差量」合成从未
  /// 存在过的混合状态。
  Future<void> clearSession(String sessionId);

  /// 现有检查点摘要（轮次升序）。
  List<CheckpointInfo> list(String sessionId);

  /// 现有检查点的轮次（升序）。
  List<int> turnsOf(String sessionId);

  /// 读某轮检查点的清单；缺失抛 [CheckpointException]。
  Future<CheckpointManifest> loadManifest(String sessionId, int turn);

  /// 把工作区恢复到 [turn] 轮的文件状态；返回恢复计数。
  ///
  /// 实现须在改动任何文件之前完成全部越界校验（fail-closed）。
  Future<CheckpointRestore> restore(String sessionId, int turn);

  /// 保留基线 + 最近 `keep - 1` 轮；`keep` 非正不裁剪。
  void prune(String sessionId);
}

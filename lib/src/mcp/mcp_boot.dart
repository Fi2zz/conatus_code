/// MCP 后台连接的状态把手。
library;

import 'dart:async';

/// 交互式启动时，MCP 握手被挪到首帧之后；[ready] 在接线（资源工具 +
/// prompt 命令）完成后 resolve。
///
/// 首轮请求前由控制器 `await`，避免模型在第一轮看不到 MCP 工具。
class McpBoot {
  final Completer<void> _done = Completer<void>();
  bool _cancelled = false;

  /// 连接与接线完成；失败也算完成（失败经告警出口报出，不阻塞首轮）。
  Future<void> get ready => _done.future;

  /// 是否已收尾。
  bool get done => _done.isCompleted;

  /// 运行时已释放：后台任务不应再把服务 / 工具挂进上下文。
  bool get cancelled => _cancelled;

  /// 取消后续接线（幂等）。
  void cancel() => _cancelled = true;

  /// 标记收尾（幂等）。
  void complete() {
    if (!_done.isCompleted) _done.complete();
  }
}

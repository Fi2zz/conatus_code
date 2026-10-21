/// XERJ 节点的最小契约：查询侧只依赖「拿到一个可用端点」。
///
/// 真实实现见 `xerj_node.dart`；测试用替身实现 [XerjEndpoint] 即可，
/// 不需要起进程或监听端口。
library;

/// 一个可用的 XERJ 节点端点。
abstract class XerjEndpoint {
  /// 确保节点可用并返回 ES 兼容端点；起不来时返回 `null`。
  ///
  /// 实现必须幂等：并发调用只启动一次，失败后不抛异常。
  Future<String?> ensureRunning();
}

/// 由本进程启动的节点进程句柄。
abstract class XerjProcess {
  /// 进程退出时完成。
  Future<void> get exited;

  /// 请求进程退出；实现可自行决定信号与兜底。
  void stop();
}

/// 启动节点进程；测试注入点。
typedef XerjProcessStarter =
    Future<XerjProcess> Function(String executable, List<String> arguments);

/// 探测某个 URL 上是否是 XERJ 节点；测试注入点。
typedef XerjHealthProbe = Future<bool> Function(String url);

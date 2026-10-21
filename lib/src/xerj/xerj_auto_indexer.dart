/// 编辑后的增量索引刷新：去抖后在后台重跑一次 `autoindex`。
///
/// XERJ 的 autoindex 不是 watcher，但重复运行是幂等、可续跑的，所以最省事的
/// 新鲜度策略是「编辑成功 → 等安静一段时间 → 再跑一次」。只在项目至少成功
/// 索引过一次之后启用（见 [XerjMarker]）。
library;

import 'dart:async';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'xerj_exec.dart';

/// 触发刷新的编辑工具（与 lint-on-edit 保持同一集合）。
const Set<String> kXerjWriteTools = <String>{
  'write_file',
  'edit_file',
  'apply_patch',
};

/// 去抖索引器。
class XerjAutoIndexer {
  XerjAutoIndexer({
    required XerjExec exec,
    required String workdir,
    this.delay = const Duration(seconds: 20),
    this.timeout = const Duration(minutes: 10),
  })  : _exec = exec,
        _workdir = workdir;

  final XerjExec _exec;
  final String _workdir;

  /// 编辑停止多久后触发。
  final Duration delay;

  /// 单次索引超时。
  final Duration timeout;

  Timer? _timer;
  bool _running = false;
  bool _pending = false;
  bool _disposed = false;

  /// 挂工具中间件：编辑成功返回后安排一次刷新。
  Disposer mount(ToolRegistry tools) => tools.use(
        (ToolCall call, Future<ToolResult> Function() next) async {
          final ToolResult result = await next();
          if (!result.isError && kXerjWriteTools.contains(call.name)) {
            schedule();
          }
          return result;
        },
      );

  /// 重新开始去抖计时。
  void schedule() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(_run()));
  }

  /// 取消待执行任务（进行中的索引不强制中断）。
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _run() async {
    if (_running) {
      _pending = true;
      return;
    }
    _running = true;
    try {
      if (!await _exec.hasIndex()) return;
      await _exec.index(_workdir, timeout);
    } finally {
      _running = false;
      if (_pending && !_disposed) {
        _pending = false;
        schedule();
      }
    }
  }
}

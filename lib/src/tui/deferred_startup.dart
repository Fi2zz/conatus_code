/// 首帧后执行的装配任务：首轮请求前由控制器等齐。
library;

import 'dart:async';
import 'dart:io';

/// 把启动时不急用的装配（文件工具、技能扫描、检查点存储）挪到首帧之后。
///
/// 交互式首帧只要求界面能画出来；这些任务在用户打第一句话之前完成即可。
/// [start] 幂等（首帧回调与首轮请求可能同时触发），单个任务失败只告警，
/// 不影响后续任务与对话。
class DeferredStartup {
  DeferredStartup({void Function(String message)? warn})
    : _warn = warn ?? stderr.writeln;

  final void Function(String message) _warn;
  final List<({String label, Future<void> Function() run})> _tasks =
      <({String label, Future<void> Function() run})>[];
  final Completer<void> _finished = Completer<void>();
  Future<void>? _done;
  bool _completed = false;

  /// 是否已开始执行。
  bool get started => _done != null;

  /// 是否已全部执行完。
  bool get completed => _completed;

  /// 全部任务跑完时 resolve（**不会**因此启动任务）。
  ///
  /// 会话绑定这类「必须等资源就绪、但又不该在首帧前抢跑」的地方用它：
  /// 等首帧回调（或首轮请求）来 [start]。
  Future<void> get done => _finished.future;

  /// 登记一项任务；必须在 [start] 之前调用。
  void add(String label, Future<void> Function() run) {
    _tasks.add((label: label, run: run));
  }

  /// 依次执行登记的任务（幂等）。
  Future<void> start() => _done ??= _runAll();

  Future<void> _runAll() async {
    for (final ({String label, Future<void> Function() run}) task in _tasks) {
      try {
        await task.run();
      } on Object catch (error) {
        _warn('${task.label}装配失败：$error');
      }
    }
    _completed = true;
    if (!_finished.isCompleted) _finished.complete();
  }
}

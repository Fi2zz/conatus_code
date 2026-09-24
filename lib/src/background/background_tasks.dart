/// 后台任务执行器：复用 `'shell'` 能力缝的 [ShellExecutor.start]。
///
/// 任务跨会话存活（根上下文服务 `'backgroundTasks'`）；沙箱内启动的后台进程
/// 照常受 CommandPolicy 形状裁决与 seatbelt 隔离。任务随 nava 进程退出而结束
/// （`keep_alive_on_exit` 本期不实现）。输出在服务内累计，`output` 读全量。
library;

import 'dart:async';

import 'package:conatus_foundation/conatus_foundation.dart';

/// 后台任务相关错误。
class BackgroundException implements Exception {
  const BackgroundException(this.code, this.message);

  /// 机器可读错误码（`limit` / `rejected`）。
  final String code;

  /// 人可读说明。
  final String message;

  @override
  String toString() => 'BackgroundException($code): $message';
}

/// 一个后台任务的只读视图。
class BackgroundTaskView {
  const BackgroundTaskView({
    required this.id,
    required this.command,
    required this.status,
    this.exitCode,
    required this.elapsedMs,
    required this.outputBytes,
  });

  final String id;
  final String command;
  final ShellProcessStatus status;
  final int? exitCode;
  final int elapsedMs;
  final int outputBytes;
}

/// 在途后台任务：持有进程句柄与累计输出。
class BackgroundTask {
  BackgroundTask({required this.id, required this.command, required this.process});

  final String id;
  final String command;
  final ShellProcess process;
  final DateTime startedAt = DateTime.now();
  final StringBuffer output = StringBuffer();

  /// 把自上次以来的增量输出并入缓冲。
  void pump() {
    final ShellProcessRead read = process.readOutput();
    if (read.delta.isNotEmpty) output.write(read.delta);
  }

  BackgroundTaskView view() => BackgroundTaskView(
        id: id,
        command: command,
        status: process.status,
        exitCode: process.exitCode,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        outputBytes: output.length,
      );
}

/// 后台任务执行器。
class BackgroundTaskService {
  BackgroundTaskService({
    required ShellExecutor shell,
    this.maxRunningTasks = 4,
    this.maxRecords = 20,
  }) : _shell = shell;

  final ShellExecutor _shell;

  /// 并发上限；非正 = 不限制。
  final int maxRunningTasks;

  /// 记录保留上限（含已完成/被杀）。
  final int maxRecords;

  final Map<String, BackgroundTask> _tasks = <String, BackgroundTask>{};
  final List<String> _order = <String>[];
  int _seq = 0;

  /// 启动一条后台命令，返回任务 id（`bg-<n>`）。
  ///
  /// 超上限抛 [BackgroundException.limit]；命令被沙箱拒绝（启动即完成且无
  /// 退出码）抛 [BackgroundException.rejected]。
  Future<String> start(String command, {String? cwd}) async {
    _enforceLimit();
    final ShellExecSpec spec = _shell.resolve(
      ShellExecRequest(command: command, workdir: cwd),
    );
    final ShellProcess process = await _shell.start(spec);
    if (process.status != ShellProcessStatus.running && process.exitCode == null) {
      throw BackgroundException('rejected', _rejectionReason(process));
    }
    final String id = 'bg-${++_seq}';
    final BackgroundTask task = BackgroundTask(id: id, command: command, process: process);
    _tasks[id] = task;
    _order.add(id);
    unawaited(process.done.then((_) => _pruneRecords()));
    return id;
  }

  /// 全部任务（含历史记录，按启动顺序）。
  List<BackgroundTaskView> list() => <BackgroundTaskView>[
        for (final String id in _order) _tasks[id]!.view(),
      ];

  /// 某任务的累计输出（先吸收增量）；id 不存在抛 [BackgroundException.notFound]。
  String output(String id) {
    final BackgroundTask? task = _tasks[id];
    if (task == null) {
      throw BackgroundException('not-found', '后台任务 $id 不存在');
    }
    task.pump();
    return task.output.toString();
  }

  /// 终止某任务；不存在抛 [BackgroundException.notFound]，已结束返回 false。
  bool kill(String id) {
    final BackgroundTask? task = _tasks[id];
    if (task == null) {
      throw BackgroundException('not-found', '后台任务 $id 不存在');
    }
    return task.process.kill();
  }

  void _enforceLimit() {
    if (maxRunningTasks <= 0) return;
    final int running = _tasks.values
        .where((BackgroundTask t) => t.process.status == ShellProcessStatus.running)
        .length;
    if (running >= maxRunningTasks) {
      throw BackgroundException('limit', '已达后台任务上限（$maxRunningTasks）');
    }
  }

  String _rejectionReason(ShellProcess process) {
    final String reason = process.readOutput().delta;
    return reason.isEmpty ? '命令被沙箱拒绝' : reason;
  }

  void _pruneRecords() {
    while (_order.length > maxRecords &&
        !_isRunning(_order.first)) {
      _tasks.remove(_order.removeAt(0));
    }
  }

  bool _isRunning(String id) =>
      _tasks[id]?.process.status == ShellProcessStatus.running;
}

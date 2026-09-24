/// 后台任务的假 shell / 假进程（脚本化 start 结果）。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 脚本化后台进程：可预置状态、输出与 kill 行为。
class FakeShellProcess implements ShellProcess {
  FakeShellProcess({
    ShellProcessStatus status = ShellProcessStatus.running,
    this.exitCode,
    this.outputs = const <String>[],
    this.killResult = false,
  }) : _status = status;

  ShellProcessStatus _status;
  @override
  int? exitCode;
  final List<String> outputs;
  final bool killResult;
  int _reads = 0;
  bool killed = false;

  @override
  ShellProcessStatus get status => _status;

  /// 模拟进程正常结束。
  void complete() => _status = ShellProcessStatus.completed;

  @override
  Future<void> get done => Future<void>.value();

  @override
  ShellProcessRead readOutput() {
    if (_reads >= outputs.length) return const ShellProcessRead(delta: '');
    return ShellProcessRead(delta: outputs[_reads++]);
  }

  @override
  bool kill() {
    killed = true;
    _status = ShellProcessStatus.killed;
    return killResult;
  }
}

/// 脚本化 shell：按顺序返回假进程；`run` 不应被后台路径调用。
class FakeBackgroundShell implements ShellExecutor {
  FakeBackgroundShell(this.processes);

  final List<FakeShellProcess> processes;
  final List<String> startedCommands = <String>[];
  int _index = 0;

  @override
  ShellExecSpec resolve(ShellExecRequest request) => ShellExecSpec(
        command: request.command,
        workdir: request.workdir ?? '.',
        timeoutMs: request.timeoutMs ?? 30000,
        stdoutMaxBytes: request.stdoutMaxBytes ?? 64000,
      );

  @override
  Future<ShellRunResult> run(ShellExecSpec spec) async =>
      throw UnimplementedError('后台路径不应调用 run');

  @override
  Future<ShellProcess> start(ShellExecSpec spec) async {
    startedCommands.add(spec.command);
    return processes[_index++];
  }
}

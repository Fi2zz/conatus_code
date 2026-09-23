/// 沙箱后台进程句柄与缓冲工具（内部实现，不对外导出）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'sandboxed_launcher.dart';

/// 沙箱后台进程句柄：缓冲输出，增量读取。
class SandboxedShellProcess implements ShellProcess {
  SandboxedShellProcess(this._process, int maxBytes) {
    _process.stdout.listen((List<int> chunk) {
      _lossy = appendBytes(_stdout, chunk, maxBytes) || _lossy;
    });
    _process.stderr.listen((List<int> chunk) {
      _lossy = appendBytes(_stderr, chunk, maxBytes) || _lossy;
    });
    _done = _process.exitCode.then((int code) {
      _exitCode = code;
      if (_status == ShellProcessStatus.running) {
        _status = ShellProcessStatus.completed;
      }
    });
  }

  final Process _process;
  final List<int> _stdout = <int>[];
  final List<int> _stderr = <int>[];
  late final Future<void> _done;
  ShellProcessStatus _status = ShellProcessStatus.running;
  int? _exitCode;
  int _outOffset = 0;
  int _errOffset = 0;
  bool _lossy = false;

  @override
  ShellProcessStatus get status => _status;

  @override
  int? get exitCode => _exitCode;

  @override
  Future<void> get done => _done;

  @override
  ShellProcessRead readOutput() {
    final String out =
        utf8.decode(_stdout.sublist(_outOffset), allowMalformed: true);
    _outOffset = _stdout.length;
    final String err =
        utf8.decode(_stderr.sublist(_errOffset), allowMalformed: true);
    _errOffset = _stderr.length;
    final String delta = _joinOutput(out, err);
    return ShellProcessRead(delta: delta, lossy: _lossy);
  }

  @override
  bool kill() {
    if (_status != ShellProcessStatus.running) return false;
    _status = ShellProcessStatus.killed;
    _process.kill();
    Timer(const Duration(milliseconds: 250), () {
      _process.kill(ProcessSignal.sigkill);
    });
    return true;
  }

  static String _joinOutput(String out, String err) {
    if (err.isEmpty) return out;
    final String section = '[stderr]\n$err';
    return out.isEmpty ? section : '$out\n$section';
  }
}

/// 命令被策略拒绝时的假进程句柄：立即完成，读输出得拒绝理由。
class RejectedShellProcess implements ShellProcess {
  RejectedShellProcess(this._reason);

  final String _reason;
  bool _read = false;

  @override
  ShellProcessStatus get status => ShellProcessStatus.completed;

  @override
  int? get exitCode => null;

  @override
  Future<void> get done => Future<void>.value();

  @override
  ShellProcessRead readOutput() {
    if (_read) return const ShellProcessRead(delta: '');
    _read = true;
    return ShellProcessRead(delta: '命令被拒绝：$_reason');
  }

  @override
  bool kill() => false;
}

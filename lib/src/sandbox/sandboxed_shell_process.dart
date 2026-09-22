/// 沙箱后台进程句柄与流工具（内部实现，不对外导出）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

/// 把 [chunk] 追加到 [bytes]，超过 [maxBytes] 时截断并返回是否发生截断。
bool appendBytes(List<int> bytes, List<int> chunk, int maxBytes) {
  if (bytes.length >= maxBytes) return true;
  final int remaining = maxBytes - bytes.length;
  if (chunk.length <= remaining) {
    bytes.addAll(chunk);
    return false;
  }
  bytes.addAll(chunk.sublist(0, remaining));
  return true;
}

/// 丢弃文本中以 `[Launcher] ` 开头的日志行。
String stripLauncherLines(String text) {
  final List<String> kept = <String>[
    for (final String line in text.split('\n'))
      if (!line.startsWith('[Launcher] ')) line,
  ];
  return kept.join('\n');
}

/// 沙箱后台进程句柄：缓冲输出（stderr 剥离 launcher 日志行），增量读取。
class SandboxedShellProcess implements ShellProcess {
  SandboxedShellProcess(this._process, int maxBytes) {
    _process.stdout.listen((List<int> chunk) {
      _lossy = appendBytes(_stdout, chunk, maxBytes) || _lossy;
    });
    _process.stderr.listen((List<int> chunk) {
      _lossy = _appendStripped(chunk, maxBytes) || _lossy;
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
  String _lineBuffer = '';
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

  /// 增量消费 stderr：按行缓冲，丢弃 launcher 日志行。
  bool _appendStripped(List<int> chunk, int maxBytes) {
    _lineBuffer += utf8.decode(chunk, allowMalformed: true);
    bool lossy = false;
    int start = 0;
    while (true) {
      final int nl = _lineBuffer.indexOf('\n', start);
      if (nl < 0) break;
      final String line = _lineBuffer.substring(start, nl);
      start = nl + 1;
      if (line.startsWith('[Launcher] ')) continue;
      lossy = appendBytes(_stderr, utf8.encode('$line\n'), maxBytes) || lossy;
    }
    _lineBuffer = _lineBuffer.substring(start);
    return lossy;
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

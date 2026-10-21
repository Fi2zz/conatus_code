import 'dart:async';
import 'dart:io';

import 'package:conatus_code/src/xerj/xerj_binary.dart';
import 'package:conatus_code/src/xerj/xerj_endpoint.dart';
import 'package:conatus_code/src/xerj/xerj_node.dart';
import 'package:test/test.dart';

/// 可观测的节点进程替身。
class _FakeProcess implements XerjProcess {
  final Completer<void> _exit = Completer<void>();

  bool stopped = false;

  @override
  Future<void> get exited => _exit.future;

  @override
  void stop() {
    stopped = true;
    exitNow();
  }

  void exitNow() {
    if (!_exit.isCompleted) _exit.complete();
  }
}

/// 按序列返回健康检查结果的探针。
class _SequenceProbe {
  _SequenceProbe(this.answers);

  /// 依次返回；用尽后重复最后一个值。
  final List<bool> answers;

  int calls = 0;

  Future<bool> call(String url) async {
    final int index = calls++;
    return index < answers.length ? answers[index] : answers.last;
  }
}

void main() {
  late Directory dir;
  late List<List<String>> starts;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-xerj-node-');
    starts = <List<String>>[];
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  XerjNode build({
    required _SequenceProbe probe,
    required _FakeProcess process,
    Duration timeout = const Duration(milliseconds: 200),
  }) => XerjNode(
    binary: const XerjBinary('xerj'),
    dataDir: '${dir.path}/data',
    startTimeout: timeout,
    probe: probe.call,
    starter: (String exe, List<String> args) async {
      starts.add(<String>[exe, ...args]);
      return process;
    },
  );

  group('XerjNode', () {
    test('已有 xerj 节点 → 复用，不启动进程', () async {
      final _FakeProcess process = _FakeProcess();
      final XerjNode node = build(
        probe: _SequenceProbe(<bool>[true]),
        process: process,
      );

      expect(await node.ensureRunning(), 'http://127.0.0.1:19200');
      expect(starts, isEmpty);
      expect(node.owned, isFalse);

      await node.dispose();
      expect(process.stopped, isFalse);
    });

    test('没有节点 → 启动并以固定参数等待就绪', () async {
      final _FakeProcess process = _FakeProcess();
      final XerjNode node = build(
        probe: _SequenceProbe(<bool>[false, true]),
        process: process,
      );

      expect(await node.ensureRunning(), 'http://127.0.0.1:19200');
      expect(node.owned, isTrue);
      expect(starts.single, <String>[
        'xerj',
        '--insecure',
        '--data-dir',
        '${dir.path}/data',
        '--port',
        '19200',
      ]);
      expect(Directory('${dir.path}/data').existsSync(), isTrue);

      await node.dispose();
      expect(process.stopped, isTrue);
    });

    test('进程提前退出 → 返回 null 并停止', () async {
      final _FakeProcess process = _FakeProcess();
      final XerjNode node = build(
        probe: _SequenceProbe(<bool>[false]),
        process: process,
      );

      final Future<String?> running = node.ensureRunning();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      process.exitNow();

      expect(await running, isNull);
      expect(process.stopped, isTrue);
    });

    test('启动超时 → 返回 null 并停止', () async {
      final _FakeProcess process = _FakeProcess();
      final XerjNode node = build(
        probe: _SequenceProbe(<bool>[false]),
        process: process,
        timeout: const Duration(milliseconds: 120),
      );

      final Stopwatch watch = Stopwatch()..start();
      expect(await node.ensureRunning(), isNull);
      watch.stop();

      expect(watch.elapsedMilliseconds, lessThan(1000));
      expect(process.stopped, isTrue);
    });

    test('并发调用只启动一次', () async {
      final _FakeProcess process = _FakeProcess();
      final XerjNode node = build(
        probe: _SequenceProbe(<bool>[false, true]),
        process: process,
      );

      final List<String?> results = await Future.wait(<Future<String?>>[
        node.ensureRunning(),
        node.ensureRunning(),
      ]);

      expect(results, <String>[
        'http://127.0.0.1:19200',
        'http://127.0.0.1:19200',
      ]);
      expect(starts, hasLength(1));
      await node.dispose();
    });

    test('dispose 幂等', () async {
      final _FakeProcess process = _FakeProcess();
      final XerjNode node = build(
        probe: _SequenceProbe(<bool>[false, true]),
        process: process,
      );

      await node.ensureRunning();
      await node.dispose();
      await node.dispose();

      expect(process.stopped, isTrue);
    });
  });
}

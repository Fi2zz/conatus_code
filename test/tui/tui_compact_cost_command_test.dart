/// `/compact` / `/cost` 命令：手动压缩与成本展示。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 脚本化 LLM：记录是否收到汇总调用。
class _ScriptedProvider implements LlmProvider {
  int summarizeCalls = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    summarizeCalls++;
    return const LlmResult(content: '摘要', provider: 's', model: 'm');
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 假压缩引擎：可脚本化返回 null（历史太短）或固定结果。
class _ScriptedCompactor implements CompactionEngine {
  _ScriptedCompactor({this.result});

  final CompactionResult? result;
  bool called = false;
  int? keepRecentArg;

  @override
  int get keepRecent => 200;

  @override
  String? summaryOf(String sessionId) => null;

  @override
  void forget(String sessionId) {}

  @override
  Future<CompactionResult?> compactIfNeeded(
    Session session,
    Summarizer summarize, {
    int? keepRecent,
  }) async {
    called = true;
    keepRecentArg = keepRecent;
    return result;
  }
}

/// 固定压缩结果（折叠 10 条）。
CompactionResult _sampleResult() => const CompactionResult(
      compactionId: 'c1',
      startSeq: 1,
      summarySeq: 2,
      endSeq: 3,
      summary: '摘要',
      shadowedSeqs: <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      kept: 20,
    );

/// 建控制器；[configure] 在会话装配前挂假服务到根上下文。
Future<(ConatusTuiController, Context)> _build({
  _ScriptedCompactor? compactor,
  CostTrackerImpl? costTracker,
}) async {
  final Context app = Context.root();
  provideTools(app);
  final _ScriptedProvider llm = _ScriptedProvider();
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[llm]));
  if (compactor != null) {
    app.provide('compaction', compactor);
  }
  if (costTracker != null) {
    app.provide('costTracker', costTracker);
  }
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    onExit: () {},
  );
  await controller.start();
  return (controller, app);
}

void main() {
  group('/compact', () {
    test('压缩成功：提示已压缩条数，keepRecent 用手动值', () async {
      final _ScriptedCompactor compactor =
          _ScriptedCompactor(result: _sampleResult());
      final (ConatusTuiController controller, Context app) = await _build(
        compactor: compactor,
      );
      addTearDown(app.dispose);

      await controller.handleLine('/compact');

      expect(compactor.called, isTrue);
      expect(compactor.keepRecentArg, kManualCompactKeepRecent);
      expect(controller.transcript.messages.last.text, contains('已压缩 10 条'));
    });

    test('历史太短：提示无需压缩，不报错', () async {
      final _ScriptedCompactor compactor = _ScriptedCompactor();
      final (ConatusTuiController controller, Context app) = await _build(
        compactor: compactor,
      );
      addTearDown(app.dispose);

      await controller.handleLine('/compact');

      expect(compactor.called, isTrue);
      expect(controller.transcript.messages.last.text, contains('无需压缩'));
    });

    test('未装配压缩服务：提示不可用', () async {
      final (ConatusTuiController controller, Context app) = await _build();
      addTearDown(app.dispose);

      await controller.handleLine('/compact');

      expect(controller.transcript.messages.last.text, contains('压缩不可用'));
    });
  });

  group('/cost', () {
    test('展示估算成本与 token 数', () async {
      final CostTrackerImpl tracker = CostTrackerImpl();
      tracker.recordUsage(<String, Object?>{
        'prompt_tokens': 1000000,
        'completion_tokens': 100000,
      });
      final (ConatusTuiController controller, Context app) = await _build(
        costTracker: tracker,
      );
      addTearDown(app.dispose);

      await controller.handleLine('/cost');

      final String text = controller.transcript.messages.last.text;
      expect(text, contains(r'$0.4200'));
      expect(text, contains('1000000'));
      expect(text, contains('100000'));
    });

    test('未装配成本追踪：提示不可用', () async {
      final (ConatusTuiController controller, Context app) = await _build();
      addTearDown(app.dispose);

      await controller.handleLine('/cost');

      expect(controller.transcript.messages.last.text, contains('成本追踪不可用'));
    });
  });

  test('命令表包含 compact 与 cost', () {
    expect(tuiCommands.any((TuiCommand c) => c.name == 'compact'), isTrue);
    expect(tuiCommands.any((TuiCommand c) => c.name == 'cost'), isTrue);
  });
}

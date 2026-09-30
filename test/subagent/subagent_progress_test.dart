/// 子 Agent 屏上回执与独立预算。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

/// 记下每次收到的消息体量。
class _UsageProvider implements LlmProvider {
  _UsageProvider(this.script, {this.promptTokens = 1000});

  final List<LlmResult> script;
  final int promptTokens;
  int calls = 0;

  @override
  String get name => 'usage';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final int index = calls < script.length ? calls : script.length - 1;
    calls++;
    return LlmResult(
      content: script[index].content,
      provider: 'usage',
      model: 'm',
      toolCalls: script[index].toolCalls,
      usage: <String, dynamic>{'prompt_tokens': promptTokens},
    );
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async* {
    final LlmResult result = await chat(
      messages,
      options: options,
      tools: tools,
    );
    // 正文与用量都要有：BudgetedLlmProvider 走 streamChatResult，正文来自增量。
    if (result.content.isNotEmpty) yield LlmTextDelta(result.content);
    yield LlmStreamDone(usage: result.usage);
  }

  @override
  void close() {}
}

void main() {
  group('SubAgentProgressStore 屏上回执', () {
    late SubAgentProgressStore store;
    late List<String> seen;

    setUp(() {
      store = SubAgentProgressStore();
      seen = <String>[];
      store.lines.listen((SubAgentLine line) => seen.add(line.text));
    });

    tearDown(() => store.close());

    test('起手 / 工具 / 收口都出屏', () async {
      store
        ..report(const SubAgentStarted('调研 checkpoint 存储'))
        ..report(const SubAgentToolCall('rg'))
        ..report(const SubAgentToolDone('rg', false))
        ..report(const SubAgentRound(1, '输出 120 字符'))
        ..report(const SubAgentFinished('success', 3, <String>['rg']));
      await pumpEventQueue();

      expect(seen, <String>[
        '◆ 子 Agent：调研 checkpoint 存储',
        '  → rg',
        '  ✓ rg',
        '  · 第 1 轮 输出 120 字符',
        '✓ 子 Agent success：3 轮 （rg）',
      ]);
    });

    test('失败标 ✗', () async {
      store
        ..report(const SubAgentToolDone('edit_file', true))
        ..report(const SubAgentFinished('failed', 2, <String>['edit_file']));
      await pumpEventQueue();

      expect(seen.first, '  ✗ edit_file');
      expect(seen.last, contains('✗'));
      expect(store.runs, 1);
    });

    test('长任务描述截断成一行，不刷屏', () async {
      store.report(SubAgentStarted('${'很长的任务描述' * 20}\n第二行'));
      await pumpEventQueue();

      expect(seen.single.contains('\n'), isFalse);
      expect(seen.single, endsWith('…'));
    });

    test('收口摘要记进 lastSummary', () {
      store.report(
        const SubAgentFinished('success', 5, <String>['rg', 'read_file']),
      );

      expect(store.lastSummary, '5 轮 （rg、read_file）');
    });

    test('关闭后再报不抛异常', () {
      store.close();
      expect(() => store.report(const SubAgentStarted('x')), returnsNormally);
    });
  });

  group('子 Agent 预算独立于主轮次', () {
    // 护栏计的是**估算的请求消息体量**（chars/4），不是 usage.prompt_tokens。
    // 额度按实测估算值卡在「一条多一点」，使第一条过、第二条不过。
    final LlmMessage one = LlmMessage('user', 'x' * 4000);
    final int cap = estimateMessagesTokens(<LlmMessage>[one]) + 10;

    test('两个包装实例各自计数，互不影响', () async {
      // 主 Agent 的额度够发两次；子 Agent 的只够发一次。
      final TurnBudget mainBudget =
          TurnBudget(maxTokens: cap * 2, maxDuration: null);
      final TurnBudget childBudget =
          TurnBudget(maxTokens: cap, maxDuration: null);
      final BudgetedLlmProvider main0 = BudgetedLlmProvider(
        _UsageProvider(<LlmResult>[_text('主 ok')]),
        budget: mainBudget,
      );
      final BudgetedLlmProvider child0 = BudgetedLlmProvider(
        _UsageProvider(<LlmResult>[_text('子 ok')]),
        budget: childBudget,
      );

      expect((await main0.chat(<LlmMessage>[one])).content, '主 ok');
      expect((await child0.chat(<LlmMessage>[one])).content, '子 ok');
      expect(
        (await child0.chat(<LlmMessage>[one])).content,
        kBudgetExhaustedReply,
        reason: '撞的是子 Agent 自己的额度',
      );
      // 主轮次此时只累计了自己那一次——子 Agent 的两次没记到它头上。
      expect((await main0.chat(<LlmMessage>[one])).content, '主 ok',
          reason: '子 Agent 的用量不应推进主轮次的计数器');
    });

    test('成本仍记进同一个 costTracker（那部分是真实花费）', () async {
      final CostTrackerImpl tracker = CostTrackerImpl();
      final BudgetedLlmProvider child0 = BudgetedLlmProvider(
        _UsageProvider(<LlmResult>[_text('ok')], promptTokens: 2000),
        budget: const TurnBudget(maxDuration: null),
        costTracker: tracker,
      );

      await child0.chat(<LlmMessage>[const LlmMessage('user', 'a')]);

      expect(tracker.promptTokens, 2000);
      expect(tracker.calls, 1);
    });
  });

  group('装配接线', () {
    test('spawn_agent 拿的是未包装的模型，不共用主轮次计数器', () async {
      // 这是任务 3 的关键不变量：若把 app 的 'llm'（BudgetedLlmProvider）
      // 传给 provideSpawnAgent，子 Agent 的每轮都会记进主轮次，主轮次会被
      // 提前收口。装配必须传 resolvedLlm。
      final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
        baseDir: Directory.systemTemp.createTempSync('nava-sub').path,
        providers: <ProviderConfig>[
          const ProviderConfig(
            name: 'testprov',
            baseUrl: 'https://testprov.example/v1',
            apiKey: 'k',
          ),
        ],
        provider: 'testprov',
        model: 'm1',
        retryPolicy: const RetryPolicy(maxAttempts: 1),
        interactive: false,
        webTools: false,
        skills: false,
      );
      addTearDown(runtime.dispose);

      final LlmProvider registered = runtime.app.get<LlmProvider>('llm')!;
      final SpawnAgentTool? spawn =
          runtime.app.tools.get('spawn_agent') as SpawnAgentTool?;

      expect(spawn, isNotNull);
      expect(spawn!.llm, isA<FallbackLlm>(), reason: '子 Agent 的模型应是未包预算的那一层');
      expect(
        identical(spawn.llm, registered),
        isFalse,
        reason: '共用会让子 Agent 的调用计入主轮次',
      );
      expect(spawn.childLlm, isNotNull, reason: '要有独立计数的派生工厂');
    });

    test('子 Agent 默认给只读探索工具', () async {
      final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
        baseDir: Directory.systemTemp.createTempSync('nava-sub2').path,
        providers: <ProviderConfig>[
          const ProviderConfig(
            name: 'testprov',
            baseUrl: 'https://testprov.example/v1',
            apiKey: 'k',
          ),
        ],
        provider: 'testprov',
        model: 'm1',
        retryPolicy: const RetryPolicy(maxAttempts: 1),
        interactive: false,
        webTools: false,
        skills: false,
      );
      addTearDown(runtime.dispose);

      final SpawnAgentTool spawn =
          runtime.app.tools.get('spawn_agent') as SpawnAgentTool;

      // 只读探索类默认放开：模型没传 tools 时子 Agent 也要能搜项目、定位文件
      //（此前只有 get_time/echo/read_file，等于无法定位）。
      expect(spawn.defaultTools,
          containsAll(<String>['rg', 'glob', 'list_files']));
      // 写 / 执行类不进默认白名单。
      expect(spawn.defaultTools, isNot(contains('write_file')));
      expect(spawn.defaultTools, isNot(contains('run_command')));
      // 缺省继承宿主权限。
      expect(spawn.permissionMode, SubAgentPermission.inherit);
    });

    test('headless（interactive:false）也吃 subagentPermission', () async {
      final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
        baseDir: Directory.systemTemp.createTempSync('nava-sub3').path,
        providers: <ProviderConfig>[
          const ProviderConfig(
            name: 'testprov',
            baseUrl: 'https://testprov.example/v1',
            apiKey: 'k',
          ),
        ],
        provider: 'testprov',
        model: 'm1',
        retryPolicy: const RetryPolicy(maxAttempts: 1),
        interactive: false,
        webTools: false,
        skills: false,
        subagentPermission: SubAgentPermission.readonly,
      );
      addTearDown(runtime.dispose);

      final SpawnAgentTool spawn =
          runtime.app.tools.get('spawn_agent') as SpawnAgentTool;

      expect(spawn.permissionMode, SubAgentPermission.readonly);
    });
  });
}

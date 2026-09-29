/// 成本累计：真实费率、两种 token 键名、缓存命中折价。
library;

import 'dart:convert';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// 一份只含 `testprov` 的 models.dev 响应。
String _catalogJson({
  String model = 'test-model',
  int context = 200000,
  double input = 1.0,
  double output = 3.0,
}) =>
    jsonEncode(<String, dynamic>{
      'testprov': <String, dynamic>{
        'models': <String, dynamic>{
          model: <String, dynamic>{
            'id': model,
            'name': 'Test Model',
            'tool_call': true,
            'reasoning': true,
            'limit': <String, dynamic>{'context': context},
            'cost': <String, dynamic>{'input': input, 'output': output},
            'modalities': <String, dynamic>{
              'input': <String>['text', 'image'],
            },
          },
        },
      },
    });

/// 建一个已预热的 store（走真实的 models.dev 解析路径）。
Future<ModelProfileStore> _warmStore({
  String model = 'test-model',
  int context = 200000,
  double input = 1.0,
  double output = 3.0,
}) async {
  final ModelProfileStore store = ModelProfileStore(
    client: ModelsDevClient(
      client: MockClient((_) async => http.Response(
            _catalogJson(
              model: model,
              context: context,
              input: input,
              output: output,
            ),
            200,
          )),
    ),
  );
  await store.warmUp();
  return store;
}

void main() {
  group('ModelProfileStore', () {
    test('解析出上下文窗口与价格', () async {
      final ModelProfileStore store = await _warmStore();
      addTearDown(store.close);

      final ModelProfile? profile = store.profileOf('testprov', 'test-model');
      expect(profile, isNotNull);
      expect(profile!.contextLength, 200000);
      expect(profile.inputPerMillion, 1.0);
      expect(profile.outputPerMillion, 3.0);
      expect(profile.hasContext, isTrue);
      expect(profile.hasPricing, isTrue);
    });

    test('provider 名对不上时按模型 id 跨 provider 找', () async {
      final ModelProfileStore store = await _warmStore();
      addTearDown(store.close);

      // 用户自定义的 provider 名（config 里叫什么就叫什么），窗口与价格是
      // 模型属性，不该因为名字对不上就变成未知。
      final ModelProfile? profile =
          store.profileOf('arkcli-agent-plan', 'test-model');
      expect(profile?.contextLength, 200000);
      expect(profile?.inputPerMillion, 1.0);
      expect(profile?.provider, 'arkcli-agent-plan');
    });

    test('未预热 / 查不到都返回 null（未知不是 0 值档案）', () {
      final ModelProfileStore store = ModelProfileStore(
        client: ModelsDevClient(client: MockClient((_) async => http.Response('{}', 200))),
      );
      addTearDown(store.close);

      expect(store.warmed, isFalse);
      expect(store.profileOf('testprov', 'test-model'), isNull);
    });

    test('拉取失败不抛错，保持未知（模型照常可用）', () async {
      final ModelProfileStore store = ModelProfileStore(
        client: ModelsDevClient(
          client: MockClient((_) async => http.Response('nope', 500)),
        ),
      );
      addTearDown(store.close);

      await store.warmUp();
      expect(store.warmed, isFalse);
      expect(store.profileOf('x', 'y'), isNull);
    });

    test('预热后广播 updates', () async {
      final ModelProfileStore store = ModelProfileStore(
        client: ModelsDevClient(
          client: MockClient((_) async => http.Response(_catalogJson(), 200)),
        ),
      );
      addTearDown(store.close);
      int ticks = 0;
      final sub = store.updates.listen((_) => ticks++);
      addTearDown(sub.cancel);

      await store.warmUp();
      await Future<void>.delayed(Duration.zero);

      expect(ticks, 1);
    });

    test('缓存命中价缺省时退回全价（不虚报折扣）', () {
      const ModelProfile noDiscount = ModelProfile(
        provider: 'p',
        model: 'm',
        inputPerMillion: 2,
        outputPerMillion: 4,
      );
      expect(noDiscount.effectiveCachedRate, 2);
    });
  });

  group('TokenUsage.parse', () {
    test('Chat Completions 键名', () {
      final TokenUsage usage = TokenUsage.parse(<String, dynamic>{
        'prompt_tokens': 100,
        'completion_tokens': 20,
      });
      expect(usage.prompt, 100);
      expect(usage.completion, 20);
      expect(usage.known, isTrue);
    });

    test('Responses 键名（此前读 prompt_tokens 会全落成 0）', () {
      final TokenUsage usage = TokenUsage.parse(<String, dynamic>{
        'input_tokens': 300,
        'output_tokens': 30,
      });
      expect(usage.prompt, 300);
      expect(usage.completion, 30);
    });

    test('缓存命中（两种嵌套表都收）', () {
      expect(
        TokenUsage.parse(<String, dynamic>{
          'prompt_tokens': 100,
          'prompt_tokens_details': <String, dynamic>{'cached_tokens': 40},
        }).cachedPrompt,
        40,
      );
      expect(
        TokenUsage.parse(<String, dynamic>{
          'input_tokens': 100,
          'input_tokens_details': <String, dynamic>{'cached_tokens': 60},
        }).cachedPrompt,
        60,
      );
    });

    test('缺字段 / 非数字按 0，且不算「已知」', () {
      final TokenUsage usage = TokenUsage.parse(<String, dynamic>{
        'prompt_tokens': 'x',
      });
      expect(usage.known, isFalse);
      expect(usage.prompt, 0);
    });
  });

  group('CostTrackerImpl', () {
    test('按真实费率算成本', () async {
      final ModelProfileStore store = await _warmStore();
      addTearDown(store.close);
      final CostTrackerImpl tracker = CostTrackerImpl(
        store: store,
        provider: 'testprov',
        model: 'test-model',
      );

      tracker.recordUsage(<String, dynamic>{
        'prompt_tokens': 1000000,
        'completion_tokens': 500000,
      });

      // 1M 输入 × $1 + 0.5M 输出 × $3
      expect(tracker.todayCost, closeTo(2.5, 1e-9));
    });

    test('缓存命中部分按折价计', () async {
      final ModelProfileStore store = await _warmStore();
      addTearDown(store.close);
      final CostTrackerImpl tracker = CostTrackerImpl(
        store: store,
        provider: 'testprov',
        model: 'test-model',
      );

      tracker.recordUsage(<String, dynamic>{
        'prompt_tokens': 1000000,
        'completion_tokens': 0,
        'prompt_tokens_details': <String, dynamic>{'cached_tokens': 800000},
      });

      // 20 万新 token × $1 + 80 万缓存（无折扣 → 仍按 $1）
      expect(tracker.todayCost, closeTo(1.0, 1e-9));
      expect(tracker.cachedTokens, 800000);
    });

    test('Responses 形态也算得出成本', () async {
      final ModelProfileStore store = await _warmStore(output: 10);
      addTearDown(store.close);
      final CostTrackerImpl tracker = CostTrackerImpl(
        store: store,
        provider: 'testprov',
        model: 'test-model',
      );

      tracker.recordUsage(<String, dynamic>{
        'input_tokens': 1000000,
        'output_tokens': 1000000,
      });

      // 1M × $1（input 缺省）+ 1M × $10（output）
      expect(tracker.todayCost, closeTo(11.0, 1e-9));
    });

    test('费率未知时成本为 0 且如实报未知（不编数字）', () async {
      final ModelProfileStore store = await _warmStore();
      addTearDown(store.close);
      final CostTrackerImpl tracker = CostTrackerImpl(
        store: store,
        provider: 'testprov',
        model: 'catalog 里没有这个模型',
      );

      tracker.recordUsage(<String, dynamic>{'prompt_tokens': 1000000});

      expect(tracker.todayCost, 0);
      expect(tracker.ratesKnown, isFalse);
      expect(tracker.promptTokens, 1000000, reason: 'token 数仍然要记');
    });

    test('无 store 时全部按未知处理', () {
      final CostTrackerImpl tracker = CostTrackerImpl();
      tracker.recordUsage(<String, dynamic>{'prompt_tokens': 1000});
      expect(tracker.todayCost, 0);
      expect(tracker.ratesKnown, isFalse);
      expect(tracker.contextLength, 0);
    });

    test('暴露真实上下文窗口', () async {
      final ModelProfileStore store = await _warmStore(context: 128000);
      addTearDown(store.close);
      final CostTrackerImpl tracker = CostTrackerImpl(
        store: store,
        provider: 'testprov',
        model: 'test-model',
      );
      expect(tracker.contextLength, 128000);
    });

    test('记录最近一次真实 prompt token（上下文压力）', () {
      final CostTrackerImpl tracker = CostTrackerImpl();
      tracker.recordUsage(<String, dynamic>{
        'prompt_tokens': 12345,
        'completion_tokens': 7,
      });
      expect(tracker.lastPromptTokens, 12345);
      expect(tracker.hasRealUsage, isTrue);
      expect(tracker.calls, 1);
    });

    test('用量为 0 的轮次不计入（不虚增调用数）', () {
      final CostTrackerImpl tracker = CostTrackerImpl();
      tracker.recordUsage(<String, dynamic>{});
      expect(tracker.hasRealUsage, isFalse);
      expect(tracker.calls, 0);
    });
  });
}

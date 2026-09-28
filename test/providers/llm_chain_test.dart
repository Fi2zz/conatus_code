/// `buildLlmChain`：把 `provider/model` 清单装配成「重试 + 回退」链。
library;

import 'dart:async';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/providers.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// 建一个只含指定 provider 的注册表。
ProviderRegistry _registry(List<ProviderProfile> profiles) => ProviderRegistry(
      profiles: profiles,
      currentName: profiles.first.name,
    );

ProviderProfile _profile(String name, {List<String> models = const <String>[]}) =>
    ProviderProfile(
      name: name,
      baseUrl: 'https://$name.example/v1',
      apiKey: 'test-key',
      models: models,
    );

void main() {
  group('buildLlmChain 装配', () {
    test('按清单顺序建链，每项各包一层重试', () {
      final LlmChain? chain = buildLlmChain(
        _registry(<ProviderProfile>[
          _profile('ark', models: <String>['doubao']),
          _profile('deepseek', models: <String>['chat']),
        ]),
        entries: <String>['ark/doubao', 'deepseek/chat'],
        policy: const RetryPolicy(),
      );

      expect(chain, isNotNull);
      expect(chain!.entries, <String>['ark/doubao', 'deepseek/chat']);
      expect(chain.llm.providers, hasLength(2));
      expect(chain.llm.providers.every((LlmProvider p) => p is RetryingLlm),
          isTrue, reason: '每个候选都要有自己的退避重试');
    });

    test('只配主模型时也建出单元素链（仍有重试）', () {
      final LlmChain? chain = buildLlmChain(
        _registry(<ProviderProfile>[_profile('ark', models: <String>['doubao'])]),
        entries: <String>['ark/doubao'],
        policy: const RetryPolicy(),
      );

      expect(chain!.entries, <String>['ark/doubao']);
      expect(chain.llm.providers.single, isA<RetryingLlm>());
    });

    test('全空清单返回 null（调用方据此引导去 /provider）', () {
      final LlmChain? chain = buildLlmChain(
        _registry(<ProviderProfile>[_profile('ark')]),
        entries: <String>[],
        policy: const RetryPolicy(),
      );
      expect(chain, isNull);
    });

    test('同名 provider 换模型也算不同候选', () {
      final LlmChain? chain = buildLlmChain(
        _registry(<ProviderProfile>[
          _profile('ark', models: <String>['pro', 'lite']),
        ]),
        entries: <String>['ark/pro', 'ark/lite'],
        policy: const RetryPolicy(),
      );
      expect(chain!.entries, <String>['ark/pro', 'ark/lite']);
    });
  });

  group('无效配置项被跳过而不是整体失败', () {
    test('provider 不存在', () {
      final LlmChain? chain = buildLlmChain(
        _registry(<ProviderProfile>[_profile('ark', models: <String>['doubao'])]),
        entries: <String>['ark/doubao', 'nope/model'],
        policy: const RetryPolicy(),
      );

      expect(chain!.entries, <String>['ark/doubao'],
          reason: '配错一条备用模型不该让主模型都用不了');
      expect(chain.skipped['nope/model'], contains('nope'));
    });

    test('重复项', () {
      final LlmChain? chain = buildLlmChain(
        _registry(<ProviderProfile>[_profile('ark', models: <String>['doubao'])]),
        entries: <String>['ark/doubao', 'ark/doubao'],
        policy: const RetryPolicy(),
      );

      expect(chain!.entries, <String>['ark/doubao']);
      expect(chain.skipped['ark/doubao'], contains('重复'));
    });

    test('缺凭据的 provider 仍进链：调用时快速失败并回退', () {
      // 不在装配期拒绝——凭据可能随后经凭据服务轮换进来。缺 Key 属于
      // 「config」类错误（不可重试），调用时立刻失败并回退到下一个候选。
      final LlmChain? chain = buildLlmChain(
        _registry(<ProviderProfile>[
          const ProviderProfile(
            name: 'ark',
            baseUrl: 'https://ark.example/v1',
            models: <String>['doubao'],
          ),
          _profile('deepseek', models: <String>['chat']),
        ]),
        entries: <String>['ark/doubao', 'deepseek/chat'],
        policy: const RetryPolicy(),
      );

      expect(chain!.entries, <String>['ark/doubao', 'deepseek/chat']);
      expect(chain.llm.providers, hasLength(2));
    });
  });

  group('LlmNotices', () {
    test('重试与回退都会发提示', () async {
      final LlmNotices notices = LlmNotices();
      addTearDown(notices.close);
      final List<LlmNotice> seen = <LlmNotice>[];
      final sub = notices.stream.listen(seen.add);
      addTearDown(sub.cancel);

      notices.onRetry(const LlmRetryAttempt(
        provider: 'ark',
        attempt: 2,
        maxAttempts: 4,
        delay: Duration(seconds: 1),
        error: LlmException('ark', 'busy', statusCode: 429),
      ));
      notices.onFallback(const LlmFallbackEvent(
        fromProvider: 'ark',
        toProvider: 'deepseek',
        error: LlmException('ark', 'boom'),
        remaining: 1,
      ));
      await pumpEventQueue();

      expect(seen.map((LlmNotice n) => n.text), <Matcher>[
        allOf(contains('ark'), contains('触发限流'), contains('2/4')),
        allOf(contains('ark 不可用'), contains('已切到 deepseek')),
      ]);
      expect(notices.lastFallback?.toProvider, 'deepseek');
    });

    test('关闭后再发提示不抛异常', () async {
      final LlmNotices notices = LlmNotices()..close();
      expect(
        () => notices.onFallback(const LlmFallbackEvent(
          fromProvider: 'a',
          toProvider: 'b',
          error: LlmException('a', 'x'),
          remaining: 0,
        )),
        returnsNormally,
      );
    });
  });

  group('doctor 展示回退链', () {
    test('装配后能报出候选数与跳过项', () {
      final Context app = Context.root();
      addTearDown(app.dispose);
      final LlmChain chain = buildLlmChain(
        _registry(<ProviderProfile>[
          _profile('ark', models: <String>['doubao']),
          _profile('deepseek', models: <String>['chat']),
        ]),
        entries: <String>['ark/doubao', 'ghost/x'],
        policy: const RetryPolicy(),
      )!;
      app.provide('llmChain', chain);

      final DoctorCheck check = doctorChecks(app)
          .firstWhere((DoctorCheck c) => c.name == '模型回退链');
      expect(check.ok, isTrue);
      expect(check.warning, isTrue, reason: '只有 1 个候选算降级配置');
      expect(check.hint, contains('ark/doubao'));
      expect(check.hint, contains('已跳过 1 条无效回退'));
    });

    test('未装配时给出引导', () {
      final Context app = Context.root();
      addTearDown(app.dispose);
      final DoctorCheck check = doctorChecks(app)
          .firstWhere((DoctorCheck c) => c.name == '模型回退链');
      expect(check.ok, isFalse);
      expect(check.hint, contains('/provider'));
    });
  });

  group('端到端：重试后回退', () {
    test('主模型限流耗尽次数，切到备选并给出回复', () async {
      var primaryCalls = 0;
      final http.Client client = _FakeClient((http.Request request, int call) {
        if (request.url.host.contains('ark')) {
          primaryCalls++;
          return http.Response('{"error":{"message":"rate limited"}}', 429,
              headers: <String, String>{'retry-after': '0'});
        }
        return http.Response(
          'data: {"choices":[{"delta":{"content":"备选答"},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: <String, String>{
            'content-type': 'text/event-stream; charset=utf-8',
          },
        );
      });

      final LlmChain chain = buildLlmChain(
        _registry(<ProviderProfile>[
          _profile('ark', models: <String>['doubao']),
          _profile('deepseek', models: <String>['chat']),
        ]),
        entries: <String>['ark/doubao', 'deepseek/chat'],
        policy: const RetryPolicy(maxAttempts: 2),
      )!;
      // 把真实构造出的 provider 换成走假 client 的版本，保持链的结构不变。
      final FallbackLlm llm = FallbackLlm(
        <LlmProvider>[
          RetryingLlm(_clientProvider('ark', 'doubao', client),
              policy: const RetryPolicy(maxAttempts: 2, jitter: 0),
              sleep: (_) async {}),
          RetryingLlm(_clientProvider('deepseek', 'chat', client),
              policy: const RetryPolicy(maxAttempts: 2, jitter: 0),
              sleep: (_) async {}),
        ],
      );
      expect(chain.llm.providers, hasLength(2));

      final LlmResult result =
          await llm.chat(<LlmMessage>[const LlmMessage('user', 'hi')]);

      expect(result.content, '备选答');
      expect(primaryCalls, 2, reason: '主模型自己重试过一次才回退');
    });
  });
}

/// 按 host 区分响应的假 HTTP client。
class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final http.Response Function(http.Request request, int call) handler;
  int _calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final int call = _calls++;
    final http.Response response = handler(request as http.Request, call);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

/// 指定 host / 假 client 的 OpenAI 兼容 provider。
LlmProvider _clientProvider(String host, String model, http.Client client) =>
    OpenAiCompatibleProvider(
      name: host,
      baseUrl: 'https://$host.example/v1',
      model: model,
      apiKey: 'k',
      client: client,
    );

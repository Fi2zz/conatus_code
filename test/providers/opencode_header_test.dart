/// OpenCode provider 的 `x-opencode-session` 注入。
library;

import 'dart:convert';

import 'package:conatus_code/providers.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

class _Recorder {
  final List<Map<String, String>> headers = <Map<String, String>>[];
  final List<http.Request> requests = <http.Request>[];

  MockClient client([String? body]) => MockClient((http.Request request) async {
        requests.add(request);
        headers.add(Map<String, String>.from(request.headers));
        return http.Response.bytes(
          utf8.encode(body ?? _chatResponse),
          200,
          headers: <String, String>{
            'content-type': 'text/event-stream; charset=utf-8',
          },
        );
      });
}

const String _chatResponse = '''
data: {"id":"1","object":"chat.completion","model":"m","choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}

data: [DONE]
''';

const List<LlmMessage> _messages = <LlmMessage>[LlmMessage('user', 'hi')];

const String _anthropicSse = '''
event: message_start
data: {"type":"message_start","message":{"model":"claude-haiku-5-5","usage":{"input_tokens":1}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ok"}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}

event: message_stop
data: {"type":"message_stop"}
''';

ProviderProfile _profile({
  required String name,
  required String baseUrl,
  String sessionHeader = '',
}) =>
    ProviderProfile(
      name: name,
      baseUrl: baseUrl,
      apiKey: 'k',
      models: <String>['glm-5.3'],
      sessionHeader: sessionHeader,
    );

void main() {
  test('OpenCode 网关按当前会话注入会话头，切换/清空即时生效', () async {
    final _Recorder recorder = _Recorder();
    final ProviderRegistry registry = ProviderRegistry(
      profiles: <ProviderProfile>[
        _profile(
          name: 'opencode-go',
          baseUrl: 'https://opencode.ai/inference/go/openai/v1',
        ),
      ],
      sessionId: 'session_abc',
      client: recorder.client(),
    );
    final LlmProvider llm = registry.buildLlm('opencode-go')!;

    await llm.chat(_messages);
    expect(recorder.headers.last['x-opencode-session'], 'ses_abc');
    expect(recorder.headers.last['User-Agent'], 'nava/0.1.0');

    registry.sessionId = 'session_def';
    await llm.chat(_messages);
    expect(recorder.headers.last['x-opencode-session'], 'ses_def');

    registry.sessionId = null;
    await llm.chat(_messages);
    expect(recorder.headers.last.containsKey('x-opencode-session'), isFalse);
  });

  test('非 OpenCode provider 不注入会话头', () async {
    final _Recorder recorder = _Recorder();
    final ProviderRegistry registry = ProviderRegistry(
      profiles: <ProviderProfile>[
        _profile(name: 'deepseek', baseUrl: 'https://api.deepseek.com/v1'),
      ],
      sessionId: 'session_abc',
      client: recorder.client(),
    );

    await registry.buildLlm('deepseek')!.chat(_messages);

    expect(recorder.headers.last.containsKey('x-opencode-session'), isFalse);
    expect(recorder.headers.last['User-Agent'], kDefaultLlmUserAgent);
  });

  test('Anthropic profile 走 /messages，Bearer + 会话头', () async {
    final _Recorder recorder = _Recorder();
    final ProviderRegistry registry = ProviderRegistry(
      profiles: <ProviderProfile>[
        const ProviderProfile(
          name: 'opencode-go-anthropic',
          baseUrl: 'https://opencode.ai/inference/go/anthropic/v1',
          apiKey: 'oc_sk',
          models: <String>['claude-haiku-5-5'],
          apiStyle: LlmApiStyle.anthropic,
        ),
      ],
      sessionId: 'session_abc',
      client: recorder.client(_anthropicSse),
    );

    await registry.buildLlm('opencode-go-anthropic')!.chat(_messages);

    final http.Request request = recorder.requests.single;
    expect(request.url.toString(), 'https://opencode.ai/inference/go/anthropic/v1/messages');
    expect(request.headers['authorization'], 'Bearer oc_sk');
    expect(request.headers['x-opencode-session'], 'ses_abc');
  });

  test('显式 session_header 覆盖自动识别（代理场景）', () async {
    final _Recorder recorder = _Recorder();
    final ProviderRegistry registry = ProviderRegistry(
      profiles: <ProviderProfile>[
        _profile(
          name: 'proxy',
          baseUrl: 'https://gateway.example/v1',
          sessionHeader: 'x-opencode-sessionid',
        ),
      ],
      sessionId: 'session_abc',
      client: recorder.client(),
    );

    await registry.buildLlm('proxy')!.chat(_messages);

    expect(recorder.headers.last['x-opencode-sessionid'], 'ses_abc');
  });
}

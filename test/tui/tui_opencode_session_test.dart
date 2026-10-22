/// 控制器绑定/解绑会话时同步 OpenCode 会话头用的 sessionId。
library;

import 'package:conatus_code/providers.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _StubProvider implements LlmProvider {
  @override
  String get name => 'stub';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async => const LlmResult(content: 'ok', provider: 'stub', model: 'm');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

void main() {
  test('绑定会话写入 registry.sessionId，解绑清空', () async {
    final Context app = Context.root();
    addTearDown(app.dispose);
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
    provideSessionLog(app, log: InMemorySessionLog());
    final ProviderRegistry registry = provideProviders(
      app,
      providers: const <ProviderProfile>[
        ProviderProfile(
          name: 'opencode-go',
          baseUrl: 'https://opencode.ai/inference/go/openai/v1',
          apiKey: 'k',
          models: <String>['glm-5.3'],
        ),
      ],
    );
    final SessionStore sessions = provideSessions(app);
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: 'test',
      initialSession: 'session_abc',
      modelLabel: 'stub',
      onExit: () {},
    );

    await controller.start();
    expect(registry.sessionId, 'session_abc');

    controller.dispose();
    expect(registry.sessionId, isNull);
  });
}

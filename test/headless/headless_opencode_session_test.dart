/// headless 一轮执行期间把会话 id 同步给 OpenCode 请求头，结束后清空。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/providers.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _CapturingProvider implements LlmProvider {
  final List<String?> seen = <String?>[];
  String? Function()? currentSession;

  @override
  String get name => 'capture';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    seen.add(currentSession?.call());
    return const LlmResult(content: 'ok', provider: 'capture', model: 'm');
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

void main() {
  test('headless 运行期间 sessionId 指向当前会话，结束后清空', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('nava-headless-session-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final _CapturingProvider provider = _CapturingProvider();
    final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
      baseDir: dir.path,
      webTools: false,
      skills: false,
      interactive: false,
      llm: FallbackLlm(<LlmProvider>[provider]),
      providers: const <ProviderConfig>[
        ProviderConfig(
          name: 'opencode-go',
          baseUrl: 'https://opencode.ai/inference/go/openai/v1',
          apiKey: 'k',
        ),
      ],
      provider: 'opencode-go',
      model: 'glm-5.3',
    );
    addTearDown(runtime.dispose);
    // 用捕获型 provider 观察运行时 registry 的当前会话 id。
    final ProviderRegistry registry = runtime.app.providers!;
    provider.currentSession = () => registry.sessionId;

    final HeadlessResult result = await runHeadless(runtime, prompt: 'hi');

    expect(provider.seen.single, result.sessionId);
    expect(registry.sessionId, isNull);
  });
}

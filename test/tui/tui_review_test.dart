/// `/review` 命令：审查提示词触发。
library;

import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _CaptureProvider implements LlmProvider {
  final List<String> prompts = <String>[];

  @override
  String get name => 'capture';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    prompts.add(messages.last.content);
    return const LlmResult(content: '审查完成。', provider: 's', model: 'm');
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

void main() {
  test('/review 提交审查提示词（含 git_diff 与只审不改）', () async {
    final Context app = Context.root();
    provideTools(app);
    final _CaptureProvider provider = _CaptureProvider();
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[provider]));
    final SessionStore sessions = provideSessions(app);
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: 'test',
      modelLabel: 'mock',
      onExit: () {},
    );
    addTearDown(app.dispose);
    await controller.start();

    await controller.handleLine('/review');

    expect(provider.prompts.single, contains('git_diff'));
    expect(provider.prompts.single, contains('只审不改'));
    expect(provider.prompts.single, contains('安全隐患'));
  });

  test('命令表包含 review', () {
    expect(tuiCommands.any((TuiCommand c) => c.name == 'review'), isTrue);
  });
}

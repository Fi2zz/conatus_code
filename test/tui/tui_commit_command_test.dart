/// `/commit` 命令：提交流程提示词触发。
library;

import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 记录收到的提示词并回一句固定回复。
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
    return const LlmResult(content: '已提交。', provider: 's', model: 'm');
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
  test('/commit 提交提交流程提示词（含 git_commit 指引）', () async {
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

    await controller.handleLine('/commit');

    expect(provider.prompts.single, contains('git_diff --staged'));
    expect(provider.prompts.single, contains('git_commit'));
    expect(provider.prompts.single, contains('Conventional Commits'));
  });

  test('命令表包含 commit', () {
    expect(tuiCommands.any((TuiCommand c) => c.name == 'commit'), isTrue);
  });
}

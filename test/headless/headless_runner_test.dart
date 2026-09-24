/// headless：单轮执行跑通、text/json 输出、会话恢复。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 按脚本返回结果的假 provider。
class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this._replies);

  final List<LlmResult> _replies;
  int _index = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      _replies[_index++];

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

/// 建一个 headless runtime（不装交互件）。
Future<ConatusTuiRuntime> _runtime(LlmProvider llm) async {
  final Directory dir = Directory.systemTemp.createTempSync('nava-headless');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String sep = Platform.pathSeparator;
  return ConatusTuiRuntime.create(
    baseDir: dir.path,
    sessionDir: dir.path,
    memoryFile: '${dir.path}${sep}memory.json',
    webTools: false,
    skills: false,
    llm: FallbackLlm(<LlmProvider>[llm]),
    interactive: false,
  );
}

void main() {
  test('跑一轮：新建会话、返回回复与退出码 0', () async {
    final ConatusTuiRuntime runtime = await _runtime(
      _ScriptedProvider(
        <LlmResult>[const LlmResult(content: '修好了。', provider: 's', model: 'm')],
      ),
    );
    addTearDown(runtime.dispose);

    final HeadlessResult result =
        await runHeadless(runtime, prompt: '把 lint 修一下');

    expect(result.exitCode, 0);
    expect(result.reply, '修好了。');
    expect(result.sessionId, startsWith('session_'));
  });

  test('指定会话 id：恢复而非新建', () async {
    final ConatusTuiRuntime runtime = await _runtime(
      _ScriptedProvider(
        <LlmResult>[const LlmResult(content: 'ok', provider: 's', model: 'm')],
      ),
    );
    addTearDown(runtime.dispose);
    final String id = runtime.sessions.create().id;

    final HeadlessResult result =
        await runHeadless(runtime, prompt: 'hi', sessionId: id);

    expect(result.sessionId, id);
  });

  test('renderHeadless：text 原样，json 单行含 reply/sessionId/exitCode', () {
    const HeadlessResult result = HeadlessResult(
      exitCode: 0,
      reply: '完成\n下一行',
      sessionId: 'session_x',
    );

    expect(renderHeadless(result, HeadlessFormat.text), '完成\n下一行');

    final Object? decoded =
        jsonDecode(renderHeadless(result, HeadlessFormat.json));
    final Map<String, Object?> map = decoded as Map<String, Object?>;
    expect(map['reply'], '完成\n下一行');
    expect(map['sessionId'], 'session_x');
    expect(map['exitCode'], 0);
    expect(renderHeadless(result, HeadlessFormat.json).contains('\n'), isFalse);
  });

  test('模型调用失败向上抛，由调用方映射退出码', () async {
    final ConatusTuiRuntime runtime = await _runtime(
      _ScriptedProvider(<LlmResult>[
        const LlmResult(content: '', provider: 's', model: 'm'),
      ]),
    );
    addTearDown(runtime.dispose);

    // 空回复也能收口；真正失败（provider 抛错）由 _ScriptedProvider 模拟：
    final _ScriptedProvider failing = _ScriptedProvider(const <LlmResult>[]);
    final ConatusTuiRuntime failingRuntime = await _runtime(failing);
    addTearDown(failingRuntime.dispose);

    await expectLater(
      runHeadless(failingRuntime, prompt: 'x'),
      throwsA(isA<LlmException>()),
    );
  });
}

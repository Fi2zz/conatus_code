/// headless 下 story 开启仍直写（无人审阅）。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

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
  }) async => _replies[_index++];

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

Future<ConatusTuiRuntime> _runtime(
  LlmProvider llm,
  Directory dir, {
  bool storyEnabled = true,
}) async {
  final String sep = Platform.pathSeparator;
  return ConatusTuiRuntime.create(
    baseDir: dir.path,
    sessionDir: dir.path,
    memoryFile: '${dir.path}${sep}memory.json',
    workdir: dir.path,
    fs: LocalFileSystem(cwd: dir.path),
    webTools: false,
    skills: false,
    interactive: false,
    llm: FallbackLlm(<LlmProvider>[llm]),
    story: StoryConfig(enabled: storyEnabled),
  );
}

LlmResult _writeReply() => const LlmResult(
      content: '',
      provider: 's',
      model: 'm',
      toolCalls: <LlmToolCall>[
        LlmToolCall(
          id: 'c1',
          name: 'write',
          arguments: '{"path":"a.txt","content":"hello"}',
        ),
      ],
    );

void main() {
  test('story 开启时 headless 仍直写', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('nava-headless-story-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final ConatusTuiRuntime runtime = await _runtime(
      _ScriptedProvider(<LlmResult>[
        _writeReply(),
        const LlmResult(content: '完成', provider: 's', model: 'm'),
      ]),
      dir,
    );
    addTearDown(runtime.dispose);
    final SessionLog log = runtime.app.get<SessionLog>('sessionLog')!;

    final HeadlessResult result =
        await runHeadless(runtime, prompt: '写一个文件');

    expect(result.exitCode, 0);
    expect(File('${dir.path}/a.txt').readAsStringSync(), 'hello');
    final List<SessionEvent> events = <SessionEvent>[];
    await log.replay(result.sessionId, events.add);
    expect(
      events.where((SessionEvent e) => e.type == kDocPatchEvent),
      isNotEmpty,
    );
  });

  test('story 关闭时 headless 不装配故事层（无 doc 事件）', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('nava-headless-nostory-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final ConatusTuiRuntime runtime = await _runtime(
      _ScriptedProvider(<LlmResult>[
        _writeReply(),
        const LlmResult(content: '完成', provider: 's', model: 'm'),
      ]),
      dir,
      storyEnabled: false,
    );
    addTearDown(runtime.dispose);
    final InMemorySessionLog log = InMemorySessionLog();
    runtime.app.provide('sessionLog', log);

    final HeadlessResult result =
        await runHeadless(runtime, prompt: '写一个文件');

    final List<SessionEvent> events = <SessionEvent>[];
    await log.replay(result.sessionId, events.add);
    expect(
      events.where((SessionEvent e) => e.type == kDocPatchEvent),
      isEmpty,
    );
  });
}

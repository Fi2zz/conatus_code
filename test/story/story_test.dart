/// 故事层薄接入：编辑工具成功结果落成补丁，`/story` 列出时间轴。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/fs_tools.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_doc/conatus_doc.dart';
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

/// 装配：内存 SessionLog + 临时目录 fs + write/edit/apply_patch + 故事层。
Future<(Context, DocEngine, InMemorySessionLog, Directory)> _build() async {
  final Directory dir = Directory.systemTemp.createTempSync('nava-story-');
  final Context app = Context.root();
  provideTools(app);
  final FileSystem fs = provideFileSystemLocal(
    app,
    fs: LocalFileSystem(cwd: dir.path),
  );
  provideFsTools(app, options: FsToolOptions(fs: fs, enableSearch: false));
  app.effect(() => app.tools.register(ApplyPatchTool(fs: fs)));
  final InMemorySessionLog log = InMemorySessionLog();
  provideSessionLog(app, log: log);
  final DocEngine engine = await provideStory(app, sessionId: 's1');
  return (app, engine, log, dir);
}

Future<List<SessionEvent>> _docEvents(InMemorySessionLog log) async {
  final List<SessionEvent> events = <SessionEvent>[];
  await log.replay('s1', events.add);
  return events.where((SessionEvent e) => e.type == kDocPatchEvent).toList();
}

void main() {
  group('provideStory', () {
    test('write 成功 → 补丁进 log、落 doc/patch 事件、fold 出文件内容', () async {
      final (
        Context app,
        DocEngine engine,
        InMemorySessionLog log,
        Directory dir,
      ) = await _build();
      addTearDown(() {
        app.dispose();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final ToolResult result = await app.tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'a.md', 'content': '你好'},
        ),
      );

      expect(result.isError, isFalse);
      expect(engine.log.length, 1);
      final DocPatch patch = engine.log.patches.single;
      expect(patch.author, PatchAuthor.ai);
      expect(patch.ops.single, isA<InsertBlockOp>());
      expect((await _docEvents(log)).length, 1);
      // 段落粒度：块 id 是 `路径#hash` 形态。
      expect(engine.state.blocks.single.id, startsWith('a.md#'));
      expect(engine.state.blocks.single.text, '你好');
    });

    test('edit 成功 → Replace op，作者为 ai', () async {
      final (Context app, DocEngine engine, _, Directory dir) = await _build();
      addTearDown(() {
        app.dispose();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      await app.tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'a.md', 'content': '旧文'},
        ),
      );

      final ToolResult result = await app.tools.call(
        const ToolCall(
          name: 'edit',
          arguments: <String, Object?>{
            'path': 'a.md',
            'old_string': '旧文',
            'new_string': '新文',
          },
        ),
      );

      expect(result.isError, isFalse);
      expect(engine.log.length, 2);
      // 段落粒度：修改 = 旧段 remove + 新段 insert（不虚构成 replace）。
      final List<PatchOp> ops = engine.log.patches[1].ops;
      expect(
        ops.map((PatchOp o) => o.runtimeType),
        containsAll(<Type>[RemoveBlockOp, InsertBlockOp]),
      );
      expect(engine.log.patches[1].author, PatchAuthor.ai);
      expect(engine.state.blocks.single.text, '新文');
    });

    test('apply_patch 多文件 → 一个补丁含全部文件的 op', () async {
      final (Context app, DocEngine engine, _, Directory dir) = await _build();
      addTearDown(() {
        app.dispose();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      File('${dir.path}/a.txt').writeAsStringSync('l1\n');
      File('${dir.path}/b.txt').writeAsStringSync('m1\n');
      const String patch = '''
--- a/a.txt
+++ b/a.txt
@@ -1,1 +1,1 @@
-l1
+l2
--- a/b.txt
+++ b/b.txt
@@ -1,1 +1,1 @@
-m1
+m2
''';

      final ToolResult result = await app.tools.call(
        const ToolCall(
          name: 'apply_patch',
          arguments: <String, Object?>{'patch': patch},
        ),
      );

      expect(result.isError, isFalse);
      expect(engine.log.length, 1);
      expect(engine.log.patches.single.ops.length, 2);
      expect(
        engine.state.blocks.map((DocBlock b) => pathOfBlock(b.id)),
        containsAll(<String>['a.txt', 'b.txt']),
      );
    });

    test('失败结果不记补丁', () async {
      final (
        Context app,
        DocEngine engine,
        InMemorySessionLog log,
        Directory dir,
      ) = await _build();
      addTearDown(() {
        app.dispose();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      File('${dir.path}/a.md').writeAsStringSync('已存在');

      final ToolResult result = await app.tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'a.md', 'content': '覆盖'},
        ),
      );

      expect(result.isError, isTrue);
      expect(engine.log.length, 0);
      expect(await _docEvents(log), isEmpty);
    });

    test('非编辑工具不产生补丁', () async {
      final (Context app, DocEngine engine, _, Directory dir) = await _build();
      addTearDown(() {
        app.dispose();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      File('${dir.path}/a.md').writeAsStringSync('内容');

      await app.tools.call(
        const ToolCall(
          name: 'read',
          arguments: <String, Object?>{'path': 'a.md'},
        ),
      );

      expect(engine.log.length, 0);
    });
  });

  group('/story 命令', () {
    test('列出补丁时间轴（序号、作者、文件）', () async {
      final Directory dir = Directory.systemTemp.createTempSync(
        'nava-story-tui-',
      );
      final Context app = Context.root();
      provideTools(app);
      provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
      provideFileSystemLocal(app, fs: LocalFileSystem(cwd: dir.path));
      provideFsTools(app, options: const FsToolOptions(enableSearch: false));
      final SessionStore sessions = provideSessions(app);
      final ConatusTuiController controller = ConatusTuiController(
        app: app,
        sessions: sessions,
        name: 'test',
        modelLabel: 'mock',
        storyEnabled: true,
        onExit: () {},
      );
      addTearDown(() {
        app.dispose();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      await controller.start();
      // 交互模式下写工具被事前审阅门拦成待定补丁，apply 后才入故事。
      await app.tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'story.md', 'content': '第一章'},
        ),
      );
      await controller.handleLine('/story apply 1');

      await controller.handleLine('/story');

      final String text = controller.transcript.messages.last.text;
      expect(text, contains('故事线（1 个补丁）'));
      expect(text, contains('[AI]'));
      expect(text, contains('story.md'));
    });
  });
}

/// `/story` 子命令：preview 渲染、discard 写回、fork 切换会话的链路。
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

/// 装配：临时目录 fs + write_file + 内存 sessionLog + 故事层。
Future<(Context, DocEngine, Directory)> _build() async {
  final Directory dir = Directory.systemTemp.createTempSync('nava-cmd-');
  final Context app = Context.root();
  provideTools(app);
  final FileSystem fs = provideFileSystemLocal(
    app,
    fs: LocalFileSystem(cwd: dir.path),
  );
  provideFsTools(app, fs: fs, enableSearch: false);
  provideSessionLog(app, log: InMemorySessionLog());
  final DocEngine engine = await provideStory(app, sessionId: 's1');
  return (app, engine, dir);
}

Future<ToolResult> _write(Context app, String path, String content) =>
    app.tools.call(
      ToolCall(
        name: 'write_file',
        arguments: <String, Object?>{'path': path, 'content': content},
      ),
    );

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
  group('/story preview', () {
    test('逐块列出并截断长文件', () async {
      final (Context app, DocEngine engine, Directory dir) = await _build();
      addTearDown(() {
        app.dispose();
        dir.deleteSync(recursive: true);
      });
      await _write(app, 'a.md', 'l1\nl2');

      final String empty = renderStoryPreview(engine.previewAt(0));
      expect(empty, contains('为空'));
      final String text = renderStoryPreview(engine.previewAt(1));
      expect(text, contains('a.md'));
      expect(text, contains('l1'));
      final String truncated = renderStoryPreview(
        engine.previewAt(1),
        maxLines: 1,
      );
      expect(truncated, contains('共 2 行'));
    });
  });

  group('/story discard', () {
    test('驳回后把触及文件写回 fold 后内容', () async {
      final (Context app, DocEngine engine, Directory dir) = await _build();
      addTearDown(() {
        app.dispose();
        dir.deleteSync(recursive: true);
      });
      await _write(app, 'a.md', '第一版');
      await app.tools.call(
        const ToolCall(
          name: 'write_file',
          arguments: <String, Object?>{
            'path': 'a.md',
            'content': '第二版',
            'mode': 'overwrite',
          },
        ),
      );
      expect(engine.log.length, 2);

      final StoryDiscardResult result = await discardStoryPatch(
        engine,
        app.require<FileSystem>('fs'),
        2,
      );

      expect(result.written, <String>['a.md']);
      expect(result.kept, isEmpty);
      expect(File('${dir.path}/a.md').readAsStringSync(), '第一版');
      expect(engine.log.patches[1].id, result.patchId);
      expect(engine.log.effective().length, 1);
    });

    test('驳回建文件的补丁：fold 后消失，文件保守保留不删', () async {
      final (Context app, DocEngine engine, Directory dir) = await _build();
      addTearDown(() {
        app.dispose();
        dir.deleteSync(recursive: true);
      });
      await _write(app, 'new.md', '全新文件');

      final StoryDiscardResult result = await discardStoryPatch(
        engine,
        app.require<FileSystem>('fs'),
        1,
      );

      expect(result.written, isEmpty);
      expect(result.kept, <String>['new.md']);
      expect(File('${dir.path}/new.md').existsSync(), isTrue);
      expect(renderStoryDiscard(result), contains('文件保留未删'));
    });

    test('序号越界抛 ArgumentError', () async {
      final (Context app, DocEngine engine, Directory dir) = await _build();
      addTearDown(() {
        app.dispose();
        dir.deleteSync(recursive: true);
      });
      expect(() => discardStoryPatch(engine, null, 1), throwsArgumentError);
    });
  });

  group('/story fork（控制器端到端）', () {
    test('fork 后切到新会话，rebuild 出分支历史', () async {
      final Directory dir = Directory.systemTemp.createTempSync(
        'nava-fork-',
      );
      final Context app = Context.root();
      provideTools(app);
      provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
      provideFileSystemLocal(app, fs: LocalFileSystem(cwd: dir.path));
      provideFsTools(app, enableSearch: false);
      provideSessionLog(app, log: InMemorySessionLog());
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
        dir.deleteSync(recursive: true);
      });
      await controller.start();
      // 交互模式下写工具被事前审阅门拦成待定补丁，逐个 apply 入故事。
      await _write(app, 'a.md', '第一章');
      await controller.handleLine('/story apply 1');
      await _write(app, 'b.md', '第二章');
      await controller.handleLine('/story apply 1');
      await controller.handleLine('/story');
      expect(controller.transcript.messages.last.text, contains('故事线（2 个补丁）'));

      await controller.handleLine('/story fork 1');

      final String announced = controller.transcript.messages.last.text;
      expect(announced, contains('分叉'));
      // 切到新会话后 rebuild：只剩前 1 个补丁的分支历史。
      await controller.handleLine('/story');
      expect(controller.transcript.messages.last.text, contains('故事线（1 个补丁）'));
      expect(controller.transcript.messages.last.text, contains('a.md'));
    });
  });
}

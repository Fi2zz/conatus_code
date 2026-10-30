/// diff 即反馈：人的编辑除 human 补丁外还生成摘要通报（待 SteeringSource
/// 轮内注入）；AI 写入 / discard 写回 / pending 应用写回不产生通报。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/fs_tools.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 装配：临时目录 fs + write + 内存 sessionLog + 故事层 + 通报队列。
Future<(Context, DocEngine, StoryNotices, Directory)> _build() async {
  final Directory dir = Directory.systemTemp.createTempSync('nava-notice-');
  final Context app = Context.root();
  provideTools(app);
  final FileSystem fs = provideFileSystemLocal(
    app,
    fs: LocalFileSystem(cwd: dir.path),
  );
  provideFsTools(app, options: FsToolOptions(fs: fs, enableSearch: false));
  provideSessionLog(app, log: InMemorySessionLog());
  final DocEngine engine = await provideStory(app, sessionId: 's1');
  final StoryNotices notices = app.require<StoryNotices>('storyNotices');
  return (app, engine, notices, dir);
}

void main() {
  group('diffLines', () {
    test('纯增加 / 纯删除 / 行内修改的行数', () {
      expect(diffLines('a\nb', 'a\nb\nc'), (added: 1, removed: 0));
      expect(diffLines('a\nb\nc', 'a\nb'), (added: 0, removed: 1));
      expect(diffLines('a\nb', 'a\nx'), (added: 1, removed: 1));
      expect(diffLines('', '新文件'), (added: 1, removed: 0));
      expect(diffLines('同', '同'), (added: 0, removed: 0));
    });
  });

  group('人的编辑通报', () {
    test('human 编辑产生通报（含路径与 +/- 行数），补丁照常登记', () async {
      final (
        Context app,
        DocEngine engine,
        StoryNotices notices,
        Directory dir,
      ) = await _build();
      addTearDown(() {
        app.dispose();
        dir.deleteSync(recursive: true);
      });
      // AI 先写 3 行（经工具，产生 ai 补丁）。
      await app.tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{
            'path': 'notes.md',
            'content': 'l1\nl2\nl3',
          },
        ),
      );
      final StoryWatcher watcher = StoryWatcher(
        engine: engine,
        dir: dir.path,
        notices: notices,
      );
      await watcher.scanOnce(); // 基线（AI 写入归因一致，无通报）

      // 人加 2 行改 0 行。
      File('${dir.path}/notes.md').writeAsStringSync('l1\nl2\nl3\nl4\nl5');
      await watcher.scanOnce();

      expect(engine.log.patches.last.author, PatchAuthor.human);
      expect(notices.length, 1);
      final String notice = notices.drain().single;
      expect(notice, contains('notes.md'));
      expect(notice, contains('+2/-0 行'));
      expect(notice, contains('修改了文件'));
      expect(notices.length, 0); // drain 一次性清空
    });

    test('人新建文件 → 通报 +n/-0', () async {
      final (
        Context app,
        DocEngine engine,
        StoryNotices notices,
        Directory dir,
      ) = await _build();
      addTearDown(() {
        app.dispose();
        dir.deleteSync(recursive: true);
      });
      final StoryWatcher watcher = StoryWatcher(
        engine: engine,
        dir: dir.path,
        notices: notices,
      );
      await watcher.scanOnce();

      File('${dir.path}/intro.md').writeAsStringSync('一\n二');
      await watcher.scanOnce();

      expect(notices.drain().single, contains('intro.md（+2/-0 行）'));
    });

    test('AI 经工具写入不产生通报（内容归因跳过）', () async {
      final (
        Context app,
        DocEngine engine,
        StoryNotices notices,
        Directory dir,
      ) = await _build();
      addTearDown(() {
        app.dispose();
        dir.deleteSync(recursive: true);
      });
      final StoryWatcher watcher = StoryWatcher(
        engine: engine,
        dir: dir.path,
        notices: notices,
      );
      await watcher.scanOnce();

      await app.tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'a.md', 'content': 'AI 写的'},
        ),
      );
      await watcher.scanOnce();

      expect(engine.log.length, 1);
      expect(engine.log.patches.single.author, PatchAuthor.ai);
      expect(notices.length, 0);
    });

    test('discard 写回与 pending 应用写回不产生通报', () async {
      final (
        Context app,
        DocEngine engine,
        StoryNotices notices,
        Directory dir,
      ) = await _build();
      addTearDown(() {
        app.dispose();
        dir.deleteSync(recursive: true);
      });
      final FileSystem fs = app.require<FileSystem>('fs');
      await app.tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'a.md', 'content': '第一版'},
        ),
      );
      await app.tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{
            'path': 'a.md',
            'content': '第二版',
            'mode': 'overwrite',
          },
        ),
      );
      final StoryWatcher watcher = StoryWatcher(
        engine: engine,
        dir: dir.path,
        notices: notices,
      );
      await watcher.scanOnce(); // 基线对齐当前状态

      // discard 驳回第二版 → 写回第一版；pending 应用再写一次——两者都与
      // 引擎 fold 一致，watcher 归因跳过。
      await discardStoryPatch(engine, fs, 2);
      final StoryPending pending = StoryPending();
      await pending.feed('''
```ops
[{"kind":"replace","blockId":"a.md","text":"第二版"}]
```
''');
      await pending.apply(1, engine, fs);
      await watcher.scanOnce();

      expect(notices.length, 0);
      expect(
        engine.log.patches.where((p) => p.author == PatchAuthor.human),
        isEmpty,
      );
    });
  });
}

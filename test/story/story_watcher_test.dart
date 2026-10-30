/// 人的编辑监听（StoryWatcher）与跨重启重建（provideStory restore）。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/fs_tools.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 装配：临时目录 fs + write + 故事层（内存 SessionLog，会话 s1）。
Future<(Context, DocEngine, Directory)> _build() async {
  final Directory dir = Directory.systemTemp.createTempSync('nava-watch-');
  final Context app = Context.root();
  provideTools(app);
  final FileSystem fs = provideFileSystemLocal(
    app,
    fs: LocalFileSystem(cwd: dir.path),
  );
  provideFsTools(app, options: FsToolOptions(fs: fs, enableSearch: false));
  provideSessionLog(app, log: InMemorySessionLog());
  final DocEngine engine = await provideStory(app, sessionId: 's1');
  return (app, engine, dir);
}

void _cleanup(Context app, Directory dir) {
  app.dispose();
  if (dir.existsSync()) dir.deleteSync(recursive: true);
}

void main() {
  group('StoryWatcher（内容归因）', () {
    test('人新建文件 → human 补丁（InsertBlockOp）', () async {
      final (Context app, DocEngine engine, Directory dir) = await _build();
      addTearDown(() => _cleanup(app, dir));
      final StoryWatcher watcher = StoryWatcher(engine: engine, dir: dir.path);
      await watcher.scanOnce(); // 建基线

      File('${dir.path}/draft.md').writeAsStringSync('第一章');

      await watcher.scanOnce();
      expect(engine.log.length, 1);
      final DocPatch patch = engine.log.patches.single;
      expect(patch.author, PatchAuthor.human);
      expect(patch.id, startsWith('human-'));
      expect(patch.ops.single, isA<InsertBlockOp>());
      expect(engine.state.blocks.single.text, '第一章');
    });

    test('人改 .py 源码 → 记 human 补丁（编码仓库常见扩展名）', () async {
      final (Context app, DocEngine engine, Directory dir) = await _build();
      addTearDown(() => _cleanup(app, dir));
      final StoryWatcher watcher = StoryWatcher(engine: engine, dir: dir.path);
      await watcher.scanOnce();

      File('${dir.path}/main.py').writeAsStringSync('print("hi")\n');

      await watcher.scanOnce();
      expect(engine.log.patches.single.author, PatchAuthor.human);
      expect(engine.state.blocks.single.id, startsWith('main.py#'));
    });

    test('rewind 写回工作区：记一次 human 补丁，重复扫描不重复记', () async {
      final (Context app, DocEngine engine, Directory dir) = await _build();
      addTearDown(() => _cleanup(app, dir));
      final StoryWatcher watcher = StoryWatcher(engine: engine, dir: dir.path);
      File('${dir.path}/draft.md').writeAsStringSync('原稿\n');
      await watcher.scanOnce(); // 基线

      File('${dir.path}/draft.md').writeAsStringSync('改过的稿\n');
      await watcher.scanOnce();
      expect(engine.log.length, 1);

      // 模拟 /rewind 把文件恢复成基线内容：watcher 只应记一条新补丁。
      File('${dir.path}/draft.md').writeAsStringSync('原稿\n');
      await watcher.scanOnce();
      await watcher.scanOnce();
      expect(engine.log.length, 2);
      expect(engine.log.patches.last.author, PatchAuthor.human);
    });

    test('AI 经工具写入不触发 human 补丁（内容与引擎一致）', () async {
      final (Context app, DocEngine engine, Directory dir) = await _build();
      addTearDown(() => _cleanup(app, dir));
      final StoryWatcher watcher = StoryWatcher(engine: engine, dir: dir.path);
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
    });

    test('人修改 AI 写过的文件 → human ReplaceBlockOp', () async {
      final (Context app, DocEngine engine, Directory dir) = await _build();
      addTearDown(() => _cleanup(app, dir));
      final StoryWatcher watcher = StoryWatcher(engine: engine, dir: dir.path);
      await app.tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'a.md', 'content': 'AI 初稿'},
        ),
      );
      await watcher.scanOnce();
      expect(engine.log.length, 1);

      File('${dir.path}/a.md').writeAsStringSync('AI 初稿 + 人改写的一段');
      await watcher.scanOnce();

      expect(engine.log.length, 2);
      final DocPatch patch = engine.log.patches[1];
      expect(patch.author, PatchAuthor.human);
      // 段落粒度：人改一段 = 该段 remove + insert（不虚构成 replace）。
      expect(
        patch.ops.map((PatchOp o) => o.runtimeType),
        containsAll(<Type>[RemoveBlockOp, InsertBlockOp]),
      );
      expect(
        renderFileText(blocksOfFile(engine.state, 'a.md')),
        'AI 初稿 + 人改写的一段',
      );
    });

    test('同一路径连续改动合并为一个 op；多文件合成一个补丁', () async {
      final (Context app, DocEngine engine, Directory dir) = await _build();
      addTearDown(() => _cleanup(app, dir));
      final StoryWatcher watcher = StoryWatcher(engine: engine, dir: dir.path);
      await watcher.scanOnce();

      File('${dir.path}/a.md').writeAsStringSync('第一版');
      File('${dir.path}/a.md').writeAsStringSync('第一版，加一句');
      File('${dir.path}/b.md').writeAsStringSync('另一个文件');
      await watcher.scanOnce();

      expect(engine.log.length, 1);
      final DocPatch patch = engine.log.patches.single;
      expect(patch.ops.length, 2);
      expect(renderFileText(blocksOfFile(engine.state, 'a.md')), '第一版，加一句');
    });

    test('跳过集目录与无改动不产生补丁', () async {
      final (Context app, DocEngine engine, Directory dir) = await _build();
      addTearDown(() => _cleanup(app, dir));
      final StoryWatcher watcher = StoryWatcher(engine: engine, dir: dir.path);
      await watcher.scanOnce();

      Directory('${dir.path}/.git').createSync();
      File('${dir.path}/.git/notes.md').writeAsStringSync('内部文件');
      await watcher.scanOnce();
      await watcher.scanOnce(); // 无改动

      expect(engine.log.length, 0);
    });
  });

  group('跨重启重建', () {
    test('provideStory 从 sessionLog 重建故事线，/story 数据来自持久化', () async {
      final (Context app1, DocEngine engine1, Directory dir) = await _build();
      await app1.tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'novel.md', 'content': '序章'},
        ),
      );
      expect(engine1.log.length, 1);
      final InMemorySessionLog shared =
          app1.require<SessionLog>('sessionLog') as InMemorySessionLog;
      // 注意：provideSessionLog 把 close 挂在上下文释放上，而
      // InMemorySessionLog.close 会清空内存事件——这里刻意不 dispose app1。
      // 真实场景是 JsonlSessionPersistence（close 不丢盘上数据），见
      // tui_app.dart 的 story-log 装配。

      // 新上下文 + 同一 sessionLog + 同一会话：模拟重启后恢复。
      final Context app2 = Context.root();
      addTearDown(() {
        app2.dispose();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      provideTools(app2);
      provideSessionLog(app2, log: shared);
      final DocEngine engine2 = await provideStory(app2, sessionId: 's1');

      expect(engine2.log.length, 1);
      expect(engine2.state.blocks.single.text, '序章');
      expect(renderStoryTimeline(engine2.log.patches), contains('novel.md'));
    });

    test('无 doc 事件的会话重建为空引擎，照常接受新补丁', () async {
      final Context app = Context.root();
      addTearDown(app.dispose);
      provideTools(app);
      provideSessionLog(app, log: InMemorySessionLog());

      final DocEngine engine = await provideStory(app, sessionId: 'fresh');

      expect(engine.log.length, 0);
      await engine.commit(
        const DocPatch(
          id: 'story-1-1',
          author: PatchAuthor.ai,
          ops: <PatchOp>[InsertBlockOp(blockId: 'x.md', text: 'hi')],
        ),
      );
      expect(engine.state.blocks.single.id, 'x.md');
    });
  });
}

/// 待应用补丁通道：ops 块编译、/story pending 列表、apply 应用入故事。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

const String _opsBlock = '''
```ops
[{"kind":"insert","blockId":"ch1.md","text":"第一章正文"}]
```
''';

void main() {
  group('tryCompileOps / StoryPending.feed', () {
    test('普通回复与坏 JSON 静默跳过', () async {
      final StoryPending pending = StoryPending();
      await pending.feed('这是普通回复，没有提议。');
      await pending.feed('```json\n{"a":1}\n```');
      await pending.feed('```ops\nnot json\n```');
      expect(pending.patches, isEmpty);
    });

    test('ops 块编译为待应用补丁（author ai）', () async {
      final StoryPending pending = StoryPending();
      await pending.feed('我建议这样改：\n$_opsBlock');
      expect(pending.patches.length, 1);
      expect(pending.patches.single.author, PatchAuthor.ai);
      expect(pending.patches.single.ops.single, isA<InsertBlockOp>());
      expect(renderStoryPending(pending.patches), contains('ch1.md'));
    });

    test('bindStoryPending 订阅助手消息事件', () async {
      final Context app = Context.root();
      addTearDown(app.dispose);
      final Session session = Session(id: 's');
      final StoryPending pending = StoryPending();
      bindStoryPending(app, session, pending);

      session.append(
        kAssistantMessageEvent,
        data: <String, Object?>{'text': '好的'},
      );
      session.append(
        kAssistantMessageEvent,
        data: <String, Object?>{'text': _opsBlock},
      );
      // feed 异步（记基底），泵一轮事件循环让它落定。
      await Future<void>.delayed(Duration.zero);

      expect(pending.patches.length, 1);
    });
  });

  group('StoryPending.apply', () {
    test('应用后写文件、补丁入故事、落 doc/patch 事件、pending 移除', () async {
      final Directory dir = Directory.systemTemp.createTempSync(
        'nava-pending-',
      );
      final Context app = Context.root();
      addTearDown(() {
        app.dispose();
        dir.deleteSync(recursive: true);
      });
      provideTools(app);
      final FileSystem fs = provideFileSystemLocal(
        app,
        fs: LocalFileSystem(cwd: dir.path),
      );
      final InMemorySessionLog log = InMemorySessionLog();
      provideSessionLog(app, log: log);
      final DocEngine engine = await provideStory(app, sessionId: 's1');
      final StoryPending pending = StoryPending();
      await pending.feed(_opsBlock);

      final String text = await pending.apply(1, engine, fs);

      expect(text, contains('已应用'));
      expect(File('${dir.path}/ch1.md').readAsStringSync(), '第一章正文');
      expect(engine.log.length, 1);
      expect(engine.state.blocks.single.text, '第一章正文');
      expect(pending.patches, isEmpty);
      final List<SessionEvent> events = <SessionEvent>[];
      await log.replay('s1', events.add);
      expect(events.map((SessionEvent e) => e.type), contains(kDocPatchEvent));
    });

    test('越界与 RemoveBlockOp 拒绝应用', () async {
      final Context app = Context.root();
      addTearDown(app.dispose);
      provideTools(app);
      provideSessionLog(app, log: InMemorySessionLog());
      final DocEngine engine = await provideStory(app, sessionId: 's1');
      final StoryPending pending = StoryPending();

      expect(await pending.apply(1, engine, null), contains('没有第 1 个'));

      await pending.feed('''
```ops
[{"kind":"remove","blockId":"ch1.md"}]
```
''');
      expect(await pending.apply(1, engine, null), contains('不支持'));
      expect(pending.patches.length, 1);
      expect(engine.log.length, 0);
    });
  });
}

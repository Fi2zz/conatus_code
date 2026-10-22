/// apply 冲突检测与双版本落盘：基底比对、git 式 marker、部分冲突混合、
/// watcher 归因不误报、ops 通道同样处理。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 装配：临时目录 fs + 内存引擎 + pending（无控制器，直测 pending 层）。
(Directory, FileSystem, DocEngine, StoryPending) _build() {
  final Directory dir = Directory.systemTemp.createTempSync(
    'nava-conflict-',
  );
  final FileSystem fs = LocalFileSystem(cwd: dir.path);
  final DocEngine engine = DocEngine(PatchLog(), sessionId: 's1');
  return (dir, fs, engine, StoryPending());
}

List<PatchOp> _writeOps(String path, String text) => <PatchOp>[
  InsertBlockOp(blockId: path, text: text),
];

void main() {
  group('冲突双版本', () {
    test('干净 apply：磁盘 == 基底，行为与从前一致', () async {
      final (dir, fs, engine, pending) = _build();
      addTearDown(() => dir.deleteSync(recursive: true));
      await pending.feedOps(_writeOps('a.md', 'AI 版本'), fs: fs);

      final String text = await pending.apply(1, engine, fs);

      expect(text, contains('已应用'));
      expect(text, isNot(contains('冲突')));
      expect(File('${dir.path}/a.md').readAsStringSync(), 'AI 版本');
      expect(engine.state.blocks.single.text, 'AI 版本');
    });

    test('冲突 apply：落双版本 marker，两版本内容完整，输出提示冲突', () async {
      final (dir, fs, engine, pending) = _build();
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/a.md').writeAsStringSync('基底内容');
      await pending.feedOps(_writeOps('a.md', 'AI 待定内容'), fs: fs);
      // pending 期间人直接改了同一文件。
      File('${dir.path}/a.md').writeAsStringSync('人的编辑');

      final String text = await pending.apply(1, engine, fs);

      expect(text, contains('冲突：1 个文件已留双版本'));
      final String landed = File('${dir.path}/a.md').readAsStringSync();
      expect(landed, contains(kConflictOpen));
      expect(landed, contains(kConflictSplit));
      expect(landed, contains(conflictClose(1)));
      // 人的版本在上、AI 版本在下，内容完整。
      expect(landed.indexOf('人的编辑'), lessThan(landed.indexOf('AI 待定内容')));
      // 落故事的 ops 按实际落盘文本段落化（规范化后与磁盘一致）。
      expect(
        normalizeParagraphText(
          renderFileText(blocksOfFile(engine.state, 'a.md')),
        ),
        normalizeParagraphText(landed),
      );
      // 冲突补丁在时间轴可见。
      expect(renderStoryTimeline(engine.log.patches), contains('a.md'));
    });

    test('部分冲突：干净文件正常写、冲突文件双版本，一条补丁 commit', () async {
      final (dir, fs, engine, pending) = _build();
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/clean.md').writeAsStringSync('干净基底');
      File('${dir.path}/dirty.md').writeAsStringSync('脏基底');
      await pending.feedOps(
        const <PatchOp>[
          ReplaceBlockOp(blockId: 'clean.md', text: 'AI 改干净文件'),
          ReplaceBlockOp(blockId: 'dirty.md', text: 'AI 改脏文件'),
        ],
        source: 'apply_patch',
        fs: fs,
      );
      File('${dir.path}/dirty.md').writeAsStringSync('人改了脏文件');

      final String text = await pending.apply(1, engine, fs);

      expect(text, contains('2 个文件'));
      expect(text, contains('冲突：1 个文件'));
      expect(File('${dir.path}/clean.md').readAsStringSync(), 'AI 改干净文件');
      final String dirty = File('${dir.path}/dirty.md').readAsStringSync();
      expect(dirty, contains('人改了脏文件'));
      expect(dirty, contains('AI 改脏文件'));
      expect(engine.log.length, 1);
      expect(engine.log.patches.single.ops.length, 2);
    });

    test('apply 后 watcher 归因一致，不误报 human 补丁', () async {
      final (dir, fs, engine, pending) = _build();
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/a.md').writeAsStringSync('基底');
      await pending.feedOps(_writeOps('a.md', 'AI 版本'), fs: fs);
      final StoryWatcher watcher = StoryWatcher(engine: engine, dir: dir.path);
      await watcher.scanOnce(); // 建基线
      File('${dir.path}/a.md').writeAsStringSync('人改过');
      await watcher.scanOnce(); // 人的编辑登记为 human 补丁
      expect(engine.log.patches.last.author, PatchAuthor.human);

      await pending.apply(1, engine, fs); // 冲突落双版本
      await watcher.scanOnce();

      // 双版本落盘内容与引擎 fold 一致：不再产生新的 human 补丁。
      expect(
        engine.log.patches.where((p) => p.author == PatchAuthor.human).length,
        1,
      );
    });

    test('ops 通道 pending 的冲突同样留双版本', () async {
      final (dir, fs, engine, pending) = _build();
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/ops.md').writeAsStringSync('ops 基底');
      await pending.feed('''
```ops
[{"kind":"replace","blockId":"ops.md","text":"ops 通道的 AI 版本"}]
```
''', fs: fs);
      File('${dir.path}/ops.md').writeAsStringSync('人改了 ops 目标');

      final String text = await pending.apply(1, engine, fs);

      expect(text, contains('冲突'));
      final String landed = File('${dir.path}/ops.md').readAsStringSync();
      expect(landed, contains('人改了 ops 目标'));
      expect(landed, contains('ops 通道的 AI 版本'));
    });

    test('人删除了目标文件：按冲突处理（人的版本为空段）', () async {
      final (dir, fs, engine, pending) = _build();
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/gone.md').writeAsStringSync('基底');
      await pending.feedOps(_writeOps('gone.md', 'AI 版本'), fs: fs);
      File('${dir.path}/gone.md').deleteSync();

      final String text = await pending.apply(1, engine, fs);

      expect(text, contains('冲突'));
      expect(
        File('${dir.path}/gone.md').readAsStringSync(),
        contains(kConflictOpen),
      );
    });
  });
}

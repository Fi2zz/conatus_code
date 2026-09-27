/// 归档层流式化：写入器 / 头部清单读取 / 条目流，与旧整包读写格式互通；
/// store 快照对可再生构建目录的默认排除。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

Directory _tempDir() =>
    Directory.systemTemp.createTempSync('checkpoint-streaming');

CheckpointManifest _manifest() =>
    const CheckpointManifest(kind: 'base', turn: 0);

void main() {
  group('CheckpointArchiveWriter / 读取互通', () {
    late Directory dir;

    setUp(() {
      dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    test('流式写入可被旧整包读取原样还原（含 4MB 多 chunk 文件）', () async {
      final File target = File('${dir.path}/a.cp');
      final Uint8List big = Uint8List(4 << 20);
      // 造可压缩度不一的内容，避免只测到全零捷径。
      for (int i = 0; i < big.length; i++) {
        big[i] = (i * 31 + 7) & 0xff;
      }
      final List<int> small = utf8.encode('你好，nava');

      final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
        target,
        _manifest(),
      );
      writer.addBytes('big.bin', big);
      await writer.addFile('small.txt', await _spill(dir, 'small.txt', small));
      await writer.close();

      final (CheckpointManifest _, List<CheckpointArchiveEntry> entries) =
          readCheckpointArchive(target);
      expect(entries.length, 2);
      expect(entries[0].$1, 'big.bin');
      expect(Uint8List.fromList(entries[0].$2), big);
      expect(entries[1].$1, 'small.txt');
      expect(entries[1].$2, small);
    });

    test('readCheckpointManifest 与整包读取的清单一致', () async {
      final File target = File('${dir.path}/b.cp');
      const CheckpointManifest manifest = CheckpointManifest(
        kind: 'delta',
        turn: 3,
        lastEventId: 'evt-9',
        changed: <String>['x.dart'],
        deleted: <String>['y.dart'],
      );
      final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
        target,
        manifest,
      );
      writer.addBytes('x.dart', utf8.encode('void main() {}'));
      await writer.close();

      final CheckpointManifest headOnly = await readCheckpointManifest(target);
      expect(headOnly.kind, 'delta');
      expect(headOnly.turn, 3);
      expect(headOnly.lastEventId, 'evt-9');
      expect(headOnly.changed, <String>['x.dart']);
      expect(headOnly.deleted, <String>['y.dart']);
    });

    test('readCheckpointEntries 条目与内容字节和整包读取一致', () async {
      final File target = File('${dir.path}/c.cp');
      final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
        target,
        _manifest(),
      );
      for (int i = 0; i < 20; i++) {
        writer.addBytes(
          'f${i.toString().padLeft(2, '0')}.txt',
          utf8.encode('content-$i-${'x' * 500}'),
        );
      }
      await writer.close();

      final List<CheckpointArchiveEntry> streamed = await readCheckpointEntries(
        target,
      ).toList();
      final (CheckpointManifest _, List<CheckpointArchiveEntry> whole) =
          readCheckpointArchive(target);

      expect(streamed.length, whole.length);
      for (int i = 0; i < whole.length; i++) {
        expect(streamed[i].$1, whole[i].$1);
        expect(streamed[i].$2, whole[i].$2);
      }
    });
  });

  group('快照默认排除构建目录', () {
    late Directory root;
    late Directory projectDir;
    late CheckpointStore store;

    setUp(() {
      root = _tempDir();
      projectDir = Directory('${root.path}/.conatus')..createSync();
      store = CheckpointStore(root: root.path, projectDir: projectDir.path);
      addTearDown(() => root.deleteSync(recursive: true));
    });

    void write(String rel, String content) {
      final File file = File('${root.path}/$rel');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    test('build/ .dart_tool/ node_modules/ .conatus/ 不进 base', () async {
      write('lib/main.dart', 'void main() {}');
      write('build/out.bin', 'artifact');
      write('.dart_tool/x.json', '{}');
      write('node_modules/m/index.js', '1');
      write('.conatus/local.state', 's');

      await store.snapshot('s1', 0);

      final CheckpointManifest manifest = store.manifestOf('s1', 0);
      expect(manifest.files.map((CheckpointFileEntry e) => e.path), <String>[
        'lib/main.dart',
      ]);
    });
  });
}

Future<File> _spill(Directory dir, String name, List<int> bytes) async {
  final File file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

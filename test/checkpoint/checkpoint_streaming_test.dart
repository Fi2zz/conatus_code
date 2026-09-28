/// 归档层流式化：写入器 / 头部清单读取 / 条目流，与旧整包读写格式互通；
/// store 快照对可再生构建目录的默认排除。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conatus_code/conatus_code.dart';
import 'package:crypto/crypto.dart';
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

  group('内容哈希旁挂（工作区内容只读一遍）', () {
    late Directory dir;

    setUp(() {
      dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    test('addFile 顺带算出的 sha256 与独立计算一致（多 chunk 文件）', () async {
      final Uint8List big = Uint8List(3 << 20); // > 64KB chunk，跨多块
      for (int i = 0; i < big.length; i++) {
        big[i] = (i * 17 + 3) & 0xff;
      }
      final File spill = await _spill(dir, 'big.bin', big);
      final List<int> small = utf8.encode('你好，nava');

      final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
        File('${dir.path}/h.cp'),
        _manifest(),
        collectHashes: true,
      );
      await writer.addFile('big.bin', spill);
      writer.addBytes('small.txt', small);
      await writer.close();

      expect(
        writer.hashes['big.bin'],
        sha256.convert(big).toString(),
        reason: '流式分块哈希应与整块一致',
      );
      expect(writer.hashes['small.txt'], sha256.convert(small).toString());
    });

    test('未开 collectHashes 时不收集（默认路径零额外开销）', () async {
      final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
        File('${dir.path}/n.cp'),
        _manifest(),
      );
      writer.addBytes('a.txt', utf8.encode('x'));
      await writer.close();
      expect(writer.hashes, isEmpty);
    });

    test('旁挂文件往返；缺失/损坏返回 null（调用方退化为保守判定）', () {
      final File archive = File('${dir.path}/r.cp')..writeAsStringSync('x');
      expect(readCheckpointHashes(archive), isNull, reason: '旁挂不存在');

      writeCheckpointHashes(archive, <String, String>{'a.txt': 'abc'});
      expect(readCheckpointHashes(archive), <String, String>{'a.txt': 'abc'});

      checkpointHashesFile(archive).writeAsStringSync('not gzip');
      expect(readCheckpointHashes(archive), isNull, reason: '损坏应降级');

      // 空哈希不写文件（先删掉上一步写入的旁挂，否则断言的是残留文件）。
      deleteCheckpointHashes(archive);
      writeCheckpointHashes(archive, <String, String>{});
      expect(
        checkpointHashesFile(archive).existsSync(),
        isFalse,
        reason: '空哈希不写文件',
      );

      // 删除幂等。
      deleteCheckpointHashes(archive);
    });

    test('索引重建跳过旁挂文件（不把 .hashes 当归档读头）', () async {
      final Directory root = _tempDir();
      final Directory projectDir = Directory('${root.path}/.conatus')
        ..createSync();
      addTearDown(() => root.deleteSync(recursive: true));
      final CheckpointStore store = CheckpointStore(
        root: root.path,
        projectDir: projectDir.path,
      );
      File('${root.path}/a.txt').writeAsStringSync('AAAA');
      await store.snapshot('s1', 0);
      // 旁挂文件确实与归档并存于同一目录。
      expect(
        checkpointHashesFile(store.archiveFile('s1', 0)).existsSync(),
        isTrue,
      );
      // 索引丢失后重建必须只认归档（否则会把 gzip JSON 当归档读头而抛错）。
      store.indexFile('s1').deleteSync();
      expect(store.list('s1').map((CheckpointInfo i) => i.turn), <int>[0]);
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

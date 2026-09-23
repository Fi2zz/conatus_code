import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/src/tui/tui_attachment.dart';
import 'package:conatus_code/src/tui/tui_clipboard_image.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tui-attachment-test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  File makeFile(String name, List<int> bytes) {
    final File file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(bytes);
    return file;
  }

  group('附件占位', () {
    test('图片占位带 PNG 尺寸：宽×高', () {
      // 8 字节 PNG 签名 + IHDR 宽高（大端 683×416）。
      final List<int> png = <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        ...List<int>.filled(8, 0),
        0x00, 0x00, 0x02, 0xAB, // 683
        0x00, 0x00, 0x01, 0xA0, // 416
      ];
      final File file = makeFile('shot.png', png);

      expect(
        attachmentPlaceholder(
            TuiAttachment(path: file.path, mimeType: 'image/png'), 3),
        '[image #3 (683×416)]',
      );
    });

    test('非图片占位带文件名', () {
      final File file = makeFile('note.txt', utf8.encode('hi'));

      expect(
        attachmentPlaceholder(
            TuiAttachment(path: file.path, mimeType: 'text/plain'), 1),
        '[file #1 (note.txt)]',
      );
    });

    test('extractAttachmentRefs 提取序号并移除占位', () {
      final AttachmentRefs refs = extractAttachmentRefs(
        '看一下 [image #1 (683×416)] 和 [file #2 (note.txt)] 谢谢',
      );

      expect(refs.text, '看一下 和 谢谢');
      expect(refs.indices, <int>[1, 2]);
    });

    test('同序号占位去重；无占位文本原样返回', () {
      final AttachmentRefs dup = extractAttachmentRefs(
        '[image #2 (1×1)] 重复 [image #2]',
      );
      expect(dup.indices, <int>[2]);
      expect(dup.text, '重复');

      final AttachmentRefs none = extractAttachmentRefs('普通文本');
      expect(none.indices, isEmpty);
      expect(none.text, '普通文本');
    });

    test('imageDimensions 识别 PNG / JPEG，非图片返回 null', () {
      final List<int> png = <int>[
        0x89, 0x50, 0x4E, 0x47, ...List<int>.filled(12, 0),
        0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x80,
      ];
      expect(imageDimensions(png), '256×128');
      expect(imageDimensions(utf8.encode('plain text')), isNull);
    });
  });

  group('extractPathAttachments', () {
    test('全部 token 都是存在的文件路径时识别为附件', () {
      final File png = makeFile('a.png', [1]);
      final File txt = makeFile('b.txt', [2]);

      final List<TuiAttachment> found = extractPathAttachments(
        '${png.path}\n${txt.path}',
        tempDir.path,
      );

      expect(found, hasLength(2));
      expect(found[0].path, png.path);
      expect(found[0].mimeType, 'image/png');
      expect(found[0].isImage, isTrue);
      expect(found[1].mimeType, 'text/plain');
    });

    test('file:// URL 与引号包裹的路径均可识别', () {
      final File png = makeFile('c.png', [1]);

      final List<TuiAttachment> found = extractPathAttachments(
        '"${png.path}"',
        tempDir.path,
      );
      expect(found.single.path, png.path);

      final List<TuiAttachment> viaUrl = extractPathAttachments(
        'file://${png.path}',
        tempDir.path,
      );
      expect(viaUrl.single.path, png.path);
    });

    test('相对路径以 cwd 为基准解析', () {
      final File png = makeFile('d.png', [1]);

      final List<TuiAttachment> found = extractPathAttachments(
        'd.png',
        tempDir.path,
      );
      expect(found.single.path, png.path);
    });

    test('普通文本 / 混合内容 / 不存在的路径返回空', () {
      expect(extractPathAttachments('你好 世界', tempDir.path), isEmpty);
      expect(
        extractPathAttachments(
          '${tempDir.path}/missing.png',
          tempDir.path,
        ),
        isEmpty,
      );
      final File png = makeFile('e.png', [1]);
      expect(
        extractPathAttachments('${png.path} 前面的文字', tempDir.path),
        isEmpty,
      );
    });
  });

  group('materializeAttachments', () {
    test('图片读为 LlmImage，文本内联为 <file> 块', () async {
      final File png = makeFile('f.png', [137, 80, 78, 71]);
      final File txt = makeFile('g.txt', utf8.encode('内容'));

      final AttachmentMaterialization payload = await materializeAttachments([
        TuiAttachment(path: png.path, mimeType: 'image/png'),
        TuiAttachment(path: txt.path, mimeType: 'text/plain'),
      ]);

      expect(payload.images.single.mimeType, 'image/png');
      expect(payload.inlineText, contains('<file path="${txt.path}">'));
      expect(payload.inlineText, contains('内容'));
    });

    test('超限抛 StateError', () async {
      final File png =
          makeFile('h.png', List<int>.filled(kAttachmentImageMaxBytes + 1, 0));

      expect(
        () => materializeAttachments(<TuiAttachment>[
          TuiAttachment(path: png.path, mimeType: 'image/png'),
        ]),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('pngBase64FromOsa', () {
    test('解析 osascript 十六进制输出', () {
      expect(
        pngBase64FromOsa('«data PNGf89504E»'),
        base64Encode(<int>[0x89, 0x50, 0x4E]),
      );
    });

    test('非匹配输出返回 null', () {
      expect(pngBase64FromOsa(''), isNull);
      expect(pngBase64FromOsa('«data PNGf»'), isNull);
    });
  });
}

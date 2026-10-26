import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/fs_tools.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

ToolContext _context(Map<String, Object?> args) =>
    ToolContext(ToolCall(name: 'read_file', arguments: args));

void main() {
  late Directory dir;
  late LocalFileSystem fs;
  late ReadFileTool tool;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-read-');
    fs = LocalFileSystem(cwd: dir.path);
    tool = ReadFileTool(fs: fs);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('ReadFileTool', () {
    test('默认带行号读取', () async {
      File('${dir.path}/a.txt').writeAsStringSync('hello\nworld');

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'path': 'a.txt'}));

      expect(result.isError, isFalse);
      expect(result.content, '     1\thello\n     2\tworld\n');
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['startLine'], 1);
      expect(value['endLine'], 2);
      expect(value['totalLines'], 2);
      expect(value['truncated'], isFalse);
      expect(value['version'], isA<String>());
    });

    test('offset / limit 分页', () async {
      File('${dir.path}/a.txt')
          .writeAsStringSync(List<String>.generate(10, (i) => 'line${i + 1}').join('\n'));

      final ToolResult result = await tool.call(
          _context(<String, Object?>{'path': 'a.txt', 'offset': 3, 'limit': 2}));

      expect(result.isError, isFalse);
      expect(result.content, '     3\tline3\n     4\tline4\n');
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['startLine'], 3);
      expect(value['endLine'], 4);
    });

    test('with_line_numbers=false 返回原文', () async {
      File('${dir.path}/a.txt').writeAsStringSync('a\nb');

      final ToolResult result = await tool.call(_context(
          <String, Object?>{'path': 'a.txt', 'with_line_numbers': false}));

      expect(result.content, 'a\nb');
    });

    test('maxChars 截断并标记', () async {
      File('${dir.path}/a.txt').writeAsStringSync('abcdefgh');
      final ReadFileTool clipped = ReadFileTool(fs: fs, maxChars: 4);

      final ToolResult result = await clipped.call(_context(<String, Object?>{'path': 'a.txt'}));

      expect(result.isError, isFalse);
      expect(result.content, endsWith('...(截断)'));
      expect(result.content.length, lessThanOrEqualTo(4 + '\n...(截断)'.length));
      expect((result.value! as Map<String, Object?>)['truncated'], isTrue);
    });

    test('图片返回 ToolImage 附件', () async {
      final List<int> bytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A];
      File('${dir.path}/a.png').writeAsBytesSync(bytes);

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'path': 'a.png'}));

      expect(result.isError, isFalse);
      expect(result.content, contains('图像已读取'));
      expect(result.images, hasLength(1));
      expect(result.images.single.mimeType, 'image/png');
      expect(base64Decode(result.images.single.base64Data), bytes);
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['mimeType'], 'image/png');
      expect(value['bytes'], bytes.length);
    });

    test('PDF 返回 ToolFile 附件', () async {
      final List<int> bytes = <int>[0x25, 0x50, 0x44, 0x46];
      File('${dir.path}/a.pdf').writeAsBytesSync(bytes);

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'path': 'a.pdf'}));

      expect(result.isError, isFalse);
      expect(result.content, contains('PDF 已读取'));
      expect(result.files, hasLength(1));
      expect(result.files.single.mimeType, 'application/pdf');
      expect(result.files.single.filename, 'a.pdf');
      expect(base64Decode(result.files.single.base64Data), bytes);
    });

    test('文件不存在 → FS_NOT_FOUND', () async {
      final ToolResult result =
          await tool.call(_context(<String, Object?>{'path': 'nope.txt'}));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'FS_NOT_FOUND');
    });

    test('目录 → FS_NOT_REGULAR_FILE', () async {
      final ToolResult result =
          await tool.call(_context(<String, Object?>{'path': '.'}));

      expect(result.error!.code, 'FS_NOT_REGULAR_FILE');
    });

    test('通过注册表调用时参数校验生效', () async {
      final ToolRegistry tools = ToolRegistry()..register(tool);

      final ToolResult result =
          await tools.call(const ToolCall(name: 'read_file'));

      expect(result.error!.code, 'INVALID_ARGS');
    });
  });
}

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

ToolContext _context(Map<String, Object?> args) =>
    ToolContext(ToolCall(name: 'apply_patch', arguments: args));

void main() {
  late Directory dir;
  late LocalFileSystem fs;
  late ApplyPatchTool tool;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-apply-');
    fs = LocalFileSystem(cwd: dir.path);
    tool = ApplyPatchTool(fs: fs);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('ApplyPatchTool', () {
    test('简单修改 patch 应用成功', () async {
      File('${dir.path}/a.txt').writeAsStringSync('line1\nline2\n');
      const String patch = '''
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,3 @@
 line1
-line2
+line2 changed
+line3
''';

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'patch': patch}));

      expect(result.isError, isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(),
          'line1\nline2 changed\nline3\n');
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['files'], <String>['a.txt']);
      expect(value['diff'], patch);
    });

    test('多 hunk / 多文件 patch 应用成功', () async {
      File('${dir.path}/a.txt').writeAsStringSync('l1\nl2\nl3\nl4\nl5\n');
      File('${dir.path}/b.txt').writeAsStringSync('b1\nb2\n');
      const String patch = '''
--- a/a.txt
+++ b/a.txt
@@ -1,1 +1,1 @@
-l1
+x1
@@ -5,1 +5,1 @@
-l5
+x5
--- a/b.txt
+++ b/b.txt
@@ -1,1 +1,2 @@
 b1
+b1.5
''';

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'patch': patch}));

      expect(result.isError, isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'x1\nl2\nl3\nl4\nx5\n');
      expect(File('${dir.path}/b.txt').readAsStringSync(), 'b1\nb1.5\nb2\n');
      expect(
        (result.value! as Map<String, Object?>)['files'],
        <String>['a.txt', 'b.txt'],
      );
    });

    test('上下文不匹配 → PATCH_CONTEXT', () async {
      File('${dir.path}/a.txt').writeAsStringSync('aaa\nbbb\n');
      const String patch = '''
--- a/a.txt
+++ b/a.txt
@@ -1,1 +1,1 @@
-wrong
+zzz
''';

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'patch': patch}));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'PATCH_CONTEXT');
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'aaa\nbbb\n');
    });

    test('无法解析 → PATCH_INVALID', () async {
      final ToolResult result = await tool.call(
          _context(<String, Object?>{'patch': '这不是 diff 文本'}));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'PATCH_INVALID');
    });

    test('新文件 patch（--- /dev/null）创建文件', () async {
      const String patch = '''
--- /dev/null
+++ b/new.dart
@@ -0,0 +1,2 @@
+void main() {}
+
''';

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'patch': patch}));

      expect(result.isError, isFalse);
      expect(File('${dir.path}/new.dart').readAsStringSync(), 'void main() {}\n');
    });
  });
}

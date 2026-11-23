import 'package:conatus_code/safety.dart';
import 'package:test/test.dart';

void main() {
  test('unified 更新两个文件', () {
    final List<PatchTarget> targets = patchTargets('''
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1 +1 @@
-a
+b
--- a/lib/b.dart
+++ b/lib/b.dart
''');
    expect(targets.map((PatchTarget t) => t.path), <String>[
      'lib/a.dart',
      'lib/b.dart',
    ]);
    expect(targets.every((PatchTarget t) => !t.creates), isTrue);
  });

  test('unified 新建 / 删除', () {
    final List<PatchTarget> added = patchTargets(
      '--- /dev/null\n+++ b/new.txt\n',
    );
    expect(added.single.creates, isTrue);
    final List<PatchTarget> deleted = patchTargets(
      '--- a/old.txt\n+++ /dev/null\n',
    );
    expect(deleted.single.path, 'old.txt');
    expect(deleted.single.creates, isFalse);
  });

  test('OpenCode 三种标记', () {
    final List<PatchTarget> targets = patchTargets('''
*** Begin Patch
*** Add File: a.txt
+x
*** Update File: b.txt
@@
*** Delete File: c.txt
*** End Patch
''');
    expect(targets.map((PatchTarget t) => t.path), <String>[
      'a.txt',
      'b.txt',
      'c.txt',
    ]);
    expect(targets.first.creates, isTrue);
  });

  test('无法识别时返回空列表', () {
    expect(patchTargets('not a patch'), isEmpty);
  });

  test('OpenCode 路径保留 b/ 前缀', () {
    final List<PatchTarget> targets = patchTargets(
      '*** Update File: b/foo.txt\n',
    );
    expect(targets.single.path, 'b/foo.txt');
  });

  test('hunk 内以 --- / +++ 开头的内容行不当文件头', () {
    final List<PatchTarget> targets = patchTargets('''
--- a/x.sql
+++ b/x.sql
@@ -1 +1 @@
--- old comment
+++ new comment
''');
    expect(targets.map((PatchTarget t) => t.path), <String>['x.sql']);
  });
}

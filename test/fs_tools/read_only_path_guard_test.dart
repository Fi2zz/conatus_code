/// `.opencode` 只读闸门：写/删在受保护根下一律拒绝，读全部透传。
library;

import 'dart:io';

import 'package:conatus_code/fs_tools.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late ReadOnlyPathGuard guard;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-ro-guard-');
    Directory('${dir.path}/.opencode/commands').createSync(recursive: true);
    File('${dir.path}/.opencode/commands/x.md').writeAsStringSync('before');
    guard = ReadOnlyPathGuard(
      inner: LocalFileSystem(),
      protectedRoots: defaultReadOnlyRoots(dir.path),
    );
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('write under .opencode is denied', () async {
    final FsTarget target = await guard.resolve(
      '${dir.path}/.opencode/commands/new.md',
    );
    expect(
      () => guard.writeText(target, 'x'),
      throwsA(
        isA<FsError>().having(
          (FsError e) => e.message,
          'message',
          contains('READ_ONLY_PATH'),
        ),
      ),
    );
    expect(File('${dir.path}/.opencode/commands/new.md').existsSync(), isFalse);
  });

  test('edit under .opencode is denied and bytes stay unchanged', () async {
    final FsTarget target = await guard.resolve(
      '${dir.path}/.opencode/commands/x.md',
    );
    expect(
      () => guard.editText(
        target,
        const FsEditRequest(oldString: 'before', newString: 'after'),
      ),
      throwsA(isA<FsError>()),
    );
    expect(
      File('${dir.path}/.opencode/commands/x.md').readAsStringSync(),
      'before',
    );
  });

  test('remove of .opencode entry and of the root itself is denied', () async {
    final FsTarget file = await guard.resolve(
      '${dir.path}/.opencode/commands/x.md',
    );
    expect(() => guard.remove(file), throwsA(isA<FsError>()));
    final FsTarget root = await guard.resolve('${dir.path}/.opencode');
    expect(() => guard.remove(root), throwsA(isA<FsError>()));
    expect(File('${dir.path}/.opencode/commands/x.md').existsSync(), isTrue);
  });

  test('reads pass through untouched', () async {
    final FsTarget target = await guard.resolve(
      '${dir.path}/.opencode/commands/x.md',
    );
    expect(await guard.readText(target), 'before');
    expect((await guard.stat(target))?.size, 6);
    expect(
      (await guard.listDir(
        await guard.resolve('${dir.path}/.opencode'),
      )).map((FsDirEntry e) => e.name),
      contains('commands'),
    );
    expect(guard.processPath(target), contains('.opencode'));
    expect(guard.fileUrl(target), startsWith('file:'));
    expect(await guard.lstat('${dir.path}/.opencode'), isNotNull);
  });

  test('writes outside protected roots still work', () async {
    final FsTarget target = await guard.resolve('${dir.path}/notes.txt');
    await guard.writeText(target, 'ok');
    expect(File('${dir.path}/notes.txt').readAsStringSync(), 'ok');
    await guard.editText(
      target,
      const FsEditRequest(oldString: 'ok', newString: 'ok2'),
    );
    expect(File('${dir.path}/notes.txt').readAsStringSync(), 'ok2');
    await guard.remove(target);
    expect(File('${dir.path}/notes.txt').existsSync(), isFalse);
    // `.opencode` 同级的相似名不受影响。
    final FsTarget sibling = await guard.resolve(
      '${dir.path}/.opencode-backup/x.md',
    );
    await guard.writeText(sibling, 'ok');
    expect(File('${dir.path}/.opencode-backup/x.md').existsSync(), isTrue);
  });

  test('symlink under .opencode cannot write outside', () async {
    final Directory outside = Directory.systemTemp.createTempSync('nava-out-');
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync(recursive: true);
    });
    Directory('${outside.path}/target').createSync(recursive: true);
    Link('${dir.path}/.opencode/escape').createSync('${outside.path}/target');

    final FsTarget target = await guard.resolve(
      '${dir.path}/.opencode/escape/x',
    );
    expect(() => guard.writeText(target, 'x'), throwsA(isA<FsError>()));
    expect(File('${outside.path}/target/x').existsSync(), isFalse);
  });

  test('defaultReadOnlyRoots covers project and global opencode dirs', () {
    final List<String> roots = defaultReadOnlyRoots(dir.path, home: '/home/u');
    final String sep = Platform.pathSeparator;
    expect(roots, contains('${dir.path}$sep.opencode'));
    expect(roots, contains('/home/u$sep.config${sep}opencode'));
    // 相对 workdir 也会转成绝对路径，避免与 displayPath 的绝对拼写错过。
    final List<String> relative = defaultReadOnlyRoots('rel', home: '');
    expect(relative.single, startsWith(sep));
    expect(relative.single, endsWith('${sep}rel$sep.opencode'));
  });
}

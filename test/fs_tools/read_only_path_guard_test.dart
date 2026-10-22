/// `.opencode` 只读闸门：写/删在受保护根下一律拒绝，读全部透传。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
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

  test('workdir 是符号链接别名 + .opencode 尚未创建 → 仍然拒绝', () async {
    final Directory real = Directory.systemTemp.createTempSync('nava-real-');
    addTearDown(() {
      if (real.existsSync()) real.deleteSync(recursive: true);
    });
    final String alias = '${dir.path}/alias';
    Link(alias).createSync(real.path);
    final String canonical = real.resolveSymbolicLinksSync();
    // 与 CLI 一致：fs 根用规范拼写（macOS /var → /private/var），受保护根用
    // 用户传入的字面 workdir 别名——两种拼写不同，且 .opencode 还不存在。
    final ReadOnlyPathGuard aliasGuard = ReadOnlyPathGuard(
      inner: LocalFileSystem(cwd: canonical),
      protectedRoots: defaultReadOnlyRoots(alias, home: '/home/u'),
    );

    final FsTarget target = await aliasGuard.resolve('.opencode/commands/x.md');

    expect(aliasGuard.processPath(target), startsWith(canonical));
    expect(() => aliasGuard.writeText(target, 'x'), throwsA(isA<FsError>()));
    expect(Directory('$canonical/.opencode').existsSync(), isFalse);
  });

  test('jail 后端（规范根）+ 字面 workdir + 未创建 → 拒绝', () async {
    final Directory jail = Directory('${dir.path}/jail')..createSync();
    final String canonical = jail.resolveSymbolicLinksSync();
    final ReadOnlyPathGuard jailGuard = ReadOnlyPathGuard(
      inner: JailedFileSystem(root: canonical),
      protectedRoots: defaultReadOnlyRoots(jail.path, home: '/home/u'),
    );

    final FsTarget target = await jailGuard.resolve(
      '.opencode/commands/x.md',
      cwd: canonical,
    );

    expect(() => jailGuard.writeText(target, 'x'), throwsA(isA<FsError>()));
    expect(Directory('$canonical/.opencode').existsSync(), isFalse);
  });

  test('全局 ~/.config/opencode 由 home 注入同样只读', () async {
    final Directory home = Directory.systemTemp.createTempSync('nava-home-');
    addTearDown(() {
      if (home.existsSync()) home.deleteSync(recursive: true);
    });
    Directory('${home.path}/.config/opencode').createSync(recursive: true);
    final ReadOnlyPathGuard homeGuard = ReadOnlyPathGuard(
      inner: LocalFileSystem(),
      protectedRoots: defaultReadOnlyRoots(dir.path, home: home.path),
    );

    final FsTarget target = await homeGuard.resolve(
      '${home.path}/.config/opencode/x.md',
    );

    expect(() => homeGuard.writeText(target, 'x'), throwsA(isA<FsError>()));
    expect(
      File('${home.path}/.config/opencode/x.md').existsSync(),
      isFalse,
    );
  });

  test('大小写变体 .OPENCODE 也算受保护（APFS 大小写不敏感）', () async {
    final Directory fresh = Directory('${dir.path}/fresh')..createSync();
    final ReadOnlyPathGuard freshGuard = ReadOnlyPathGuard(
      inner: LocalFileSystem(),
      protectedRoots: defaultReadOnlyRoots(fresh.path, home: '/home/u'),
    );

    final FsTarget target = await freshGuard.resolve(
      '${fresh.path}/.OPENCODE/commands/x.md',
    );

    expect(() => freshGuard.writeText(target, 'x'), throwsA(isA<FsError>()));
    expect(Directory('${fresh.path}/.OPENCODE').existsSync(), isFalse);
  });
}

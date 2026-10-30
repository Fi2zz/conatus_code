/// `.opencode` 只读策略：受保护根覆盖项目级与全局目录（产品侧策略）。
library;

import 'dart:io';

import 'package:conatus_code/fs_tools.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-ro-policy-');
    Directory('${dir.path}/.opencode/commands').createSync(recursive: true);
    File('${dir.path}/.opencode/commands/x.md').writeAsStringSync('before');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
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
    expect(File('${home.path}/.config/opencode/x.md').existsSync(), isFalse);
  });

  test('大小写变体 .OPENCODE 也算受保护（APFS 大小写不敏感）', () async {
    // 大小写折叠只在 macOS / Windows 生效（Linux 上是两个不同目录）。
    if (Platform.isLinux) return;
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

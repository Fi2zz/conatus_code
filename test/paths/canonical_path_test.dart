import 'dart:io';

import 'package:conatus_code/safety.dart';
import 'package:test/test.dart';

void main() {
  test('相对路径按 workdir 解析到真实文件', () {
    final Directory dir = Directory.systemTemp.createTempSync('nava-canon');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File file = File('${dir.path}${Platform.pathSeparator}a.txt')
      ..writeAsStringSync('x');
    expect(
      canonicalToolPath(dir.path, null, './a.txt'),
      file.resolveSymbolicLinksSync(),
    );
  });

  test('~ 展开到 home；空串返回 null', () {
    final Directory dir = Directory.systemTemp.createTempSync('nava-home');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File file = File('${dir.path}${Platform.pathSeparator}x.txt')
      ..writeAsStringSync('x');
    expect(
      canonicalToolPath(dir.path, dir.path, '~/x.txt'),
      file.resolveSymbolicLinksSync(),
    );
    expect(canonicalToolPath(dir.path, dir.path, '   '), isNull);
  });

  test('符号链接按真实目标返回', () {
    if (Platform.isWindows) return;
    final Directory dir = Directory.systemTemp.createTempSync('nava-link');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File target = File('${dir.path}${Platform.pathSeparator}t.txt')
      ..writeAsStringSync('x');
    Link(
      '${dir.path}${Platform.pathSeparator}alias.txt',
    ).createSync(target.path);
    expect(
      canonicalToolPath(dir.path, null, 'alias.txt'),
      target.resolveSymbolicLinksSync(),
    );
  });

  test('词法归一化 .. 与 .（目标不存在也不留残留段）', () {
    final Directory dir = Directory.systemTemp.createTempSync('nava-dotdot');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File file = File('${dir.path}${Platform.pathSeparator}a.txt')
      ..writeAsStringSync('x');
    expect(
      canonicalToolPath(dir.path, null, 'nope/../a.txt'),
      file.resolveSymbolicLinksSync(),
    );
  });
}

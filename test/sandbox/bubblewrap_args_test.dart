/// Linux bwrap 参数构造：只读根、可写根、网络与受保护路径。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  test('默认断网 + 工作区可写 + 受保护路径只读', () {
    final Directory dir = Directory.systemTemp.createTempSync('nava-bwrap-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final Directory opencode = Directory('${dir.path}/.opencode')
      ..createSync();
    final List<String> args = buildBubblewrapArgs(
      root: dir.path,
      workdir: '${dir.path}/work',
      writablePaths: <String>{'/tmp/cache'},
      protectedPaths: <String>{opencode.path},
      networkAllowed: false,
      command: 'echo hi',
    );

    expect(args, containsAllInOrder(<String>['--unshare-all', '--cap-drop', 'ALL']));
    expect(args, isNot(contains('--share-net')));
    expect(args, containsAllInOrder(<String>['--ro-bind', '/', '/']));
    expect(args, containsAllInOrder(<String>['--bind', dir.path, dir.path]));
    expect(args, containsAllInOrder(<String>['--bind-try', '/tmp/cache', '/tmp/cache']));
    expect(
      args,
      containsAllInOrder(<String>['--ro-bind-try', opencode.path, opencode.path]),
    );
    expect(args, containsAllInOrder(<String>['--', '/bin/sh', '-c', 'echo hi']));
  });

  test('允许网络时共享网络命名空间', () {
    final List<String> args = buildBubblewrapArgs(
      root: '/work',
      workdir: '/work',
      writablePaths: const <String>{},
      protectedPaths: const <String>{},
      networkAllowed: true,
      command: 'true',
    );

    expect(args, contains('--share-net'));
  });
}

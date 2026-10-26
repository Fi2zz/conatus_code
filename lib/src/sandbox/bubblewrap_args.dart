/// Linux bubblewrap（bwrap）参数构造。
library;

import 'dart:io';

/// 构造 bwrap 命令行参数：deny-by-default 的只读根 + 工作区可写。
List<String> buildBubblewrapArgs({
  required String root,
  required String workdir,
  required Set<String> writablePaths,
  required Set<String> protectedPaths,
  required bool networkAllowed,
  required String command,
}) {
  final List<String> args = <String>[
    '--die-with-parent',
    '--unshare-all',
    if (networkAllowed) '--share-net',
    '--new-session',
    '--cap-drop',
    'ALL',
    '--proc',
    '/proc',
    '--dev',
    '/dev',
    '--tmpfs',
    '/tmp',
    '--ro-bind',
    '/',
    '/',
    '--bind',
    root,
    root,
  ];
  for (final String path in writablePaths) {
    if (path == root) continue;
    args.addAll(<String>['--bind-try', path, path]);
  }
  for (final String path in protectedPaths) {
    if (!FileSystemEntity.isDirectorySync(path) &&
        !FileSystemEntity.isFileSync(path)) {
      continue;
    }
    args.addAll(<String>['--ro-bind-try', path, path]);
  }
  args.addAll(<String>[
    '--chdir',
    workdir,
    '--',
    '/bin/sh',
    '-c',
    command,
  ]);
  return args;
}

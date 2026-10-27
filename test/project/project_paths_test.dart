/// 工作区目录命名：可读 slug + worktree 短哈希。
library;

import 'dart:io';

import 'package:conatus_code/src/project/project_paths.dart';
import 'package:test/test.dart';

void main() {
  group('workspaceSlug', () {
    test('保留普通 basename', () {
      expect(workspaceSlug('lifts'), 'lifts');
    });

    test('空格与不安全字符折成单个连字符', () {
      expect(workspaceSlug('my project'), 'my-project');
      expect(workspaceSlug('a/b:c*'), 'a-b-c');
      expect(workspaceSlug('a---b'), 'a-b');
    });

    test('保留 Unicode 字母', () {
      expect(workspaceSlug('工作区'), '工作区');
      expect(workspaceSlug('项目 2026'), '项目-2026');
    });

    test('空串 / 纯符号回退 workspace', () {
      expect(workspaceSlug(''), 'workspace');
      expect(workspaceSlug('///'), 'workspace');
      expect(workspaceSlug('..'), 'workspace');
    });

    test('按 Unicode 字符截断到 32', () {
      expect(workspaceSlug('a' * 40), 'a' * 32);
      expect(workspaceSlug('工' * 40), '工' * 32);
    });
  });

  group('workspaceDirName', () {
    test('slug + 12 位哈希', () {
      expect(
        workspaceDirName('lifts', '3f9a2c1b7d4e0000'),
        'lifts-3f9a2c1b7d4e',
      );
    });

    test('可指定哈希长度', () {
      expect(
        workspaceDirName('lifts', '3f9a2c1b7d4e0000', hashLength: 16),
        'lifts-3f9a2c1b7d4e0000',
      );
    });

    test('空 basename 也带哈希', () {
      expect(workspaceDirName('', 'abcd'), 'workspace-abcd');
    });
  });

  test('workspacesRoot 跟随 NAVA_HOME / HOME', () {
    final String sep = Platform.pathSeparator;
    expect(
      workspacesRoot(env: <String, String>{'HOME': '/home/me'}),
      '${sep}home${sep}me$sep.nava${sep}workspaces',
    );
    expect(
      workspacesRoot(
        env: <String, String>{'HOME': '/home/me', 'NAVA_HOME': '/data/nava'},
      ),
      '${sep}data${sep}nava${sep}workspaces',
    );
  });
}

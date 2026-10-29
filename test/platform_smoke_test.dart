/// 跨平台冒烟：SQLite 项目注册表与本地文件系统在 macOS/Linux/Windows 可用。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-platform');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void main() {
  test('项目注册表可创建、重开并持久化', () {
    final Directory home = _tempDir();
    final Directory work = _tempDir();
    final String dbPath = '${home.path}${Platform.pathSeparator}projects.db';
    final String workspaces =
        '${home.path}${Platform.pathSeparator}workspaces';
    final ProjectRegistry registry = ProjectRegistry.open(
      dbPath: dbPath,
      workspacesDir: workspaces,
    );
    final WorkspaceInfo info = registry.resolve(work.path);
    registry.setIcon(info.projectId, url: '🐍', color: '#336699');
    registry.rename(info.projectId, '跨平台项目', dataDir: info.dataDir);
    registry.close();

    final ProjectRegistry reopened = ProjectRegistry.open(
      dbPath: dbPath,
      workspacesDir: workspaces,
    );
    addTearDown(reopened.close);
    final ProjectRecord project = reopened.project(info.projectId)!;
    expect(project.name, '跨平台项目');
    expect(project.iconUrl, '🐍');
    expect(project.iconColor, '#336699');
    expect(reopened.list().single.worktreePath, info.worktreePath);
    expect(Directory(info.dataDir).existsSync(), isTrue);
  });

  test('本地文件系统可写、读、删', () async {
    final Directory work = _tempDir();
    final LocalFileSystem fs = LocalFileSystem(cwd: work.path);
    final FsTarget target = await fs.resolve('smoke.txt');
    await fs.writeText(target, 'hello');
    expect(await fs.readText(target), 'hello');
    expect((await fs.stat(target))?.size, 5);
    await fs.remove(target);
    expect(await fs.stat(target), isNull);
  });
}

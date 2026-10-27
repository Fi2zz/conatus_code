/// runtime 启动：项目注册表、baseDir 绕过与 project_dir 覆盖。
library;

import 'dart:io';

import 'package:conatus_code/src/project/project_registry.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-app-project');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

Future<ConatusTuiRuntime> _runtime({
  required String workdir,
  required ProjectRegistry registry,
  String? baseDir,
  String? projectDir,
  String? temp,
}) {
  return ConatusTuiRuntime.create(
    projectRegistry: registry,
    projectDir: projectDir,
    baseDir: baseDir,
    workdir: workdir,
    sessionDir: temp == null ? null : '$temp/sessions',
    memoryFile: temp == null ? null : '$temp/memory.json',
    webTools: false,
    skills: false,
    llm: FallbackLlm(const <LlmProvider>[]),
    interactive: false,
  );
}

ProjectRegistry _registry(Directory dir) => ProjectRegistry.open(
  dbPath: '${dir.path}/projects.db',
  workspacesDir: '${dir.path}/workspaces',
);

void main() {
  test('无 baseDir：runtime 使用注册表数据目录并暴露 projectInfo', () async {
    final Directory temp = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = _registry(temp);
    final ConatusTuiRuntime runtime = await _runtime(
      workdir: work.path,
      registry: registry,
      temp: temp.path,
    );
    try {
      final WorkspaceInfo info = runtime.app.get<WorkspaceInfo>('projectInfo')!;
      expect(info.projectName, work.path.split(Platform.pathSeparator).last);
      expect(
        runtime.app.get<String>('projectDataDir'),
        registry.resolve(work.path).dataDir,
      );
    } finally {
      await runtime.dispose();
    }
  });

  test('显式 baseDir 绕过注册表', () async {
    final Directory temp = _tempDir();
    final Directory work = _tempDir();
    final Directory base = _tempDir();
    final ProjectRegistry registry = _registry(temp);
    final ConatusTuiRuntime runtime = await _runtime(
      workdir: work.path,
      registry: registry,
      baseDir: base.path,
      temp: temp.path,
    );
    try {
      expect(runtime.app.get<String>('projectDataDir'), base.path);
      expect(runtime.app.get<WorkspaceInfo>('projectInfo'), isNull);
      expect(registry.database.worktreeAt(work.path), isNull);
    } finally {
      await runtime.dispose();
      registry.close();
    }
  });

  test('git 子目录 + 相对 projectDir：数据落启动目录', () async {
    final Directory temp = _tempDir();
    final Directory repo = _tempDir();
    final Directory sub = Directory('${repo.path}/sub')..createSync();
    Process.runSync('git', <String>['init', '-q', '-b', 'main'], workingDirectory: repo.path);
    Process.runSync(
      'git',
      <String>['config', 'user.email', 'test@example.com'],
      workingDirectory: repo.path,
    );
    Process.runSync(
      'git',
      <String>['config', 'user.name', 'test'],
      workingDirectory: repo.path,
    );
    File('${repo.path}/a.txt').writeAsStringSync('a');
    Process.runSync('git', <String>['add', 'a.txt'], workingDirectory: repo.path);
    Process.runSync('git', <String>['commit', '-qm', 'init'], workingDirectory: repo.path);
    final ProjectRegistry registry = _registry(temp);
    final ConatusTuiRuntime runtime = await _runtime(
      workdir: sub.path,
      registry: registry,
      projectDir: '.conatus',
      temp: temp.path,
    );
    try {
      expect(
        runtime.app.get<String>('projectDataDir'),
        '${Directory(sub.path).resolveSymbolicLinksSync()}'
        '${Platform.pathSeparator}.conatus',
      );
    } finally {
      await runtime.dispose();
    }
  });

  test('显式 projectDir 仍登记 worktree，但数据目录用覆盖值', () async {
    final Directory temp = _tempDir();
    final Directory work = _tempDir();
    final Directory override = _tempDir();
    final ProjectRegistry registry = _registry(temp);
    final ConatusTuiRuntime runtime = await _runtime(
      workdir: work.path,
      registry: registry,
      projectDir: override.path,
      temp: temp.path,
    );
    try {
      expect(
        runtime.app.get<WorkspaceInfo>('projectInfo')!.dataDir,
        override.path,
      );
      expect(
        registry.database.worktreeAt(
          Directory(work.path).resolveSymbolicLinksSync(),
        ),
        isNotNull,
      );
    } finally {
      await runtime.dispose();
    }
  });
}

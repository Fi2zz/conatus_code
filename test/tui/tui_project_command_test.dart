/// `/project`：查看项目信息与重命名。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-project-cmd');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

Future<(ConatusTuiController, Context)> _build({
  WorkspaceInfo? info,
  ProjectRegistry? registry,
}) async {
  final Context app = Context.root();
  addTearDown(app.dispose);
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(const <LlmProvider>[]));
  final SessionStore sessions = provideSessions(app);
  if (info != null) {
    app.provide('projectDataDir', info.dataDir);
    app.provide('projectInfo', info);
  }
  if (registry != null) {
    app.provide('projectRegistry', registry);
  }
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    initialSession: 'project',
    modelLabel: 'mock',
    onExit: () {},
  );
  await controller.start();
  return (controller, app);
}

void main() {
  test('/project 展示名称、短 ID、worktree 与数据目录', () async {
    final Directory temp = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = ProjectRegistry.open(
      dbPath: '${temp.path}/projects.db',
      workspacesDir: '${temp.path}/workspaces',
    );
    addTearDown(registry.close);
    final WorkspaceInfo info = registry.resolve(work.path);
    final (ConatusTuiController controller, _) = await _build(
      info: info,
      registry: registry,
    );

    await controller.handleLine('/project');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('项目：${info.projectName}'));
    expect(text, contains('ID：${info.projectShortId}'));
    expect(text, contains('worktree：${info.worktreePath}'));
    expect(text, contains('数据目录：${info.dataDir}'));
    controller.dispose();
  });

  test('/project rename 更新注册表并提示新名字', () async {
    final Directory temp = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = ProjectRegistry.open(
      dbPath: '${temp.path}/projects.db',
      workspacesDir: '${temp.path}/workspaces',
    );
    addTearDown(registry.close);
    final WorkspaceInfo info = registry.resolve(work.path);
    final (ConatusTuiController controller, _) = await _build(
      info: info,
      registry: registry,
    );

    await controller.handleLine('/project rename 我的项目');

    expect(controller.transcript.messages.last.text, contains('我的项目'));
    expect(registry.database.project(info.projectId)!.name, '我的项目');

    await controller.handleLine('/project');
    expect(controller.transcript.messages.last.text, contains('项目：我的项目'));
    controller.dispose();
  });

  test('/project rename 拒绝空名、超长名与控制字符', () async {
    final Directory temp = _tempDir();
    final Directory work = _tempDir();
    final ProjectRegistry registry = ProjectRegistry.open(
      dbPath: '${temp.path}/projects.db',
      workspacesDir: '${temp.path}/workspaces',
    );
    addTearDown(registry.close);
    final WorkspaceInfo info = registry.resolve(work.path);
    final (ConatusTuiController controller, _) = await _build(
      info: info,
      registry: registry,
    );

    await controller.handleLine('/project rename');
    expect(controller.transcript.messages.last.text, contains('用法'));

    await controller.handleLine('/project renamefoo');
    expect(controller.transcript.messages.last.text, contains('用法'));

    await controller.handleLine('/project rename ${'a' * 81}');
    expect(controller.transcript.messages.last.text, contains('80'));

    await controller.handleLine('/project rename a\nb');
    expect(controller.transcript.messages.last.text, contains('控制字符'));

    expect(registry.database.project(info.projectId)!.name, info.projectName);
    controller.dispose();
  });

  test('没有注册表服务时提示未启用', () async {
    final (ConatusTuiController controller, _) = await _build();

    await controller.handleLine('/project');

    expect(controller.transcript.messages.last.text, contains('项目注册表未启用'));
    controller.dispose();
  });
}

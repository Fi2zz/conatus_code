/// `/worktree` 命令。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-worktree-cmd');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

Future<(ConatusTuiController, Context)> _build({
  WorktreeService? service,
  WorkspaceInfo? info,
}) async {
  final Context app = Context.root();
  addTearDown(app.dispose);
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(const <LlmProvider>[]));
  final SessionStore sessions = provideSessions(app);
  if (info != null) app.provide('projectInfo', info);
  if (service != null) app.provide('worktreeService', service);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    initialSession: 'worktree',
    modelLabel: 'mock',
    onExit: () {},
  );
  await controller.start();
  return (controller, app);
}

void main() {
  test('/worktree list 显示已登记 worktree', () async {
    final Directory home = _tempDir();
    final Directory repo = _tempDir();
    Process.runSync('git', <String>['init', '-q', '-b', 'main'], workingDirectory: repo.path);
    Process.runSync('git', <String>['config', 'user.email', 't@example.com'], workingDirectory: repo.path);
    Process.runSync('git', <String>['config', 'user.name', 't'], workingDirectory: repo.path);
    File('${repo.path}/a.txt').writeAsStringSync('a');
    Process.runSync('git', <String>['add', 'a.txt'], workingDirectory: repo.path);
    Process.runSync('git', <String>['commit', '-qm', 'init'], workingDirectory: repo.path);
    final ProjectRegistry registry = ProjectRegistry.open(
      dbPath: '${home.path}/projects.db',
      workspacesDir: '${home.path}/workspaces',
    );
    addTearDown(registry.close);
    final WorkspaceInfo info = registry.resolve(repo.path);
    final WorktreeService service = WorktreeService(
      registry: registry,
      workdir: repo.path,
      worktreesDir: '${home.path}/worktrees',
    );
    final (ConatusTuiController controller, _) = await _build(
      service: service,
      info: info,
    );

    await controller.handleLine('/worktree list');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('worktree'));
    expect(text, contains(info.worktreePath));
    expect(text, contains('*'));
    controller.dispose();
  });

  test('未装配 worktree 服务时提示', () async {
    final (ConatusTuiController controller, _) = await _build();

    await controller.handleLine('/worktree list');

    expect(controller.transcript.messages.last.text, contains('不可用'));
    controller.dispose();
  });
}

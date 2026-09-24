/// 后台任务工具：启动 / 列表 / 输出 / kill 的工具映射。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'support/fake_shell.dart';

/// 建一个带服务的上下文，工具已注册。
(Context, BackgroundTaskService, FakeBackgroundShell) _boot(
  List<FakeShellProcess> processes, {
  int maxRunningTasks = 4,
}) {
  final Context app = Context.root();
  provideTools(app);
  final FakeBackgroundShell shell = FakeBackgroundShell(processes);
  final BackgroundTaskService service = BackgroundTaskService(
    shell: shell,
    maxRunningTasks: maxRunningTasks,
  );
  app.provide('backgroundTasks', service);
  provideBackgroundTools(app, service: service);
  return (app, service, shell);
}

void main() {
  test('run_command_background 启动并返回 id；list / output / kill 打通', () async {
    final (Context app, BackgroundTaskService service, _) = _boot(
      <FakeShellProcess>[
        FakeShellProcess(outputs: <String>['编译输出'], killResult: true),
      ],
    );
    addTearDown(app.dispose);

    final ToolResult started = await app.tools.call(const ToolCall(
      name: 'run_command_background',
      arguments: <String, Object?>{'command': 'dart build'},
    ));
    expect(started.isError, isFalse);
    expect(started.content, contains('bg-1'));

    final ToolResult listed = await app.tools.call(const ToolCall(
      name: 'list_background_tasks',
    ));
    expect(listed.content, contains('bg-1'));
    expect(listed.content, contains('dart build'));

    final ToolResult output = await app.tools.call(const ToolCall(
      name: 'background_output',
      arguments: <String, Object?>{'task_id': 'bg-1'},
    ));
    expect(output.content, '编译输出');

    final ToolResult killed = await app.tools.call(const ToolCall(
      name: 'background_kill',
      arguments: <String, Object?>{'task_id': 'bg-1'},
    ));
    expect(killed.content, contains('已终止'));
  });

  test('超上限 → 工具失败（limit）；沙箱拒绝 → 失败（rejected）', () async {
    final (Context limited, _, _) = _boot(
      <FakeShellProcess>[FakeShellProcess(), FakeShellProcess()],
      maxRunningTasks: 1,
    );
    addTearDown(limited.dispose);
    await limited.tools.call(const ToolCall(
      name: 'run_command_background',
      arguments: <String, Object?>{'command': 'a'},
    ));
    final ToolResult over = await limited.tools.call(const ToolCall(
      name: 'run_command_background',
      arguments: <String, Object?>{'command': 'b'},
    ));
    expect(over.isError, isTrue);
    expect(over.error?.code, 'limit');

    final (Context rejected, _, _) = _boot(<FakeShellProcess>[
      FakeShellProcess(
        status: ShellProcessStatus.completed,
        outputs: <String>['命令被拒绝：含 &&'],
      ),
    ]);
    addTearDown(rejected.dispose);
    final ToolResult denied = await rejected.tools.call(const ToolCall(
      name: 'run_command_background',
      arguments: <String, Object?>{'command': 'a && b'},
    ));
    expect(denied.isError, isTrue);
    expect(denied.error?.code, 'rejected');
  });

  test('工具缺参 / 不存在的任务 → 失败', () async {
    final (Context app, _, _) = _boot(<FakeShellProcess>[]);
    addTearDown(app.dispose);

    final ToolResult noCommand = await app.tools.call(const ToolCall(
      name: 'run_command_background',
    ));
    expect(noCommand.isError, isTrue);

    final ToolResult noTask = await app.tools.call(const ToolCall(
      name: 'background_output',
      arguments: <String, Object?>{'task_id': 'bg-9'},
    ));
    expect(noTask.isError, isTrue);
    expect(noTask.error?.code, 'not-found');
  });
}

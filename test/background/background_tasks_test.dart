/// BackgroundTaskService：启动 / 上限 / 拒绝 / 输出累计 / kill / 记录保留。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'support/fake_shell.dart';

void main() {
  test('start 递增 id，done 后状态 completed，输出增量累计', () async {
    final FakeBackgroundShell shell = FakeBackgroundShell(<FakeShellProcess>[
      FakeShellProcess(outputs: <String>['第一段', '第二段']),
    ]);
    final BackgroundTaskService service =
        BackgroundTaskService(shell: shell, maxRunningTasks: 2);

    final String id = await service.start('dart test');

    expect(id, 'bg-1');
    expect(shell.startedCommands, <String>['dart test']);
    expect(service.list().single.status, ShellProcessStatus.running);
    // 模拟进程结束：置 completed 并 pump 一次。
    shell.processes.first.complete();
    expect(service.output(id), '第一段');
    expect(service.output(id), '第一段第二段'); // 增量并入缓冲
    expect(service.list().single.outputBytes, greaterThan(0));
  });

  test('超过 maxRunningTasks 拒绝；0 = 不限', () async {
    final FakeBackgroundShell limited = FakeBackgroundShell(<FakeShellProcess>[
      FakeShellProcess(),
      FakeShellProcess(),
    ]);
    final BackgroundTaskService service =
        BackgroundTaskService(shell: limited, maxRunningTasks: 1);
    await service.start('cmd1');
    expect(
      () => service.start('cmd2'),
      throwsA(isA<BackgroundException>().having(
          (BackgroundException e) => e.code, 'code', 'limit')),
    );

    final FakeBackgroundShell unlimited = FakeBackgroundShell(<FakeShellProcess>[
      FakeShellProcess(),
      FakeShellProcess(),
    ]);
    final BackgroundTaskService unlimitedService =
        BackgroundTaskService(shell: unlimited, maxRunningTasks: 0);
    await unlimitedService.start('a');
    await unlimitedService.start('b'); // 不抛
  });

  test('沙箱拒绝（启动即完成且无退出码）抛 rejected', () async {
    final FakeBackgroundShell shell = FakeBackgroundShell(<FakeShellProcess>[
      FakeShellProcess(status: ShellProcessStatus.completed, outputs: <String>['命令被拒绝：含 &&']),
    ]);
    final BackgroundTaskService service =
        BackgroundTaskService(shell: shell, maxRunningTasks: 2);

    await expectLater(
      service.start('a && b'),
      throwsA(isA<BackgroundException>().having(
          (BackgroundException e) => e.code, 'code', 'rejected')),
    );
  });

  test('kill 终止进程；output/kill 对不存在的 id 抛 not-found', () async {
    final FakeShellProcess process = FakeShellProcess(killResult: true);
    final FakeBackgroundShell shell =
        FakeBackgroundShell(<FakeShellProcess>[process]);
    final BackgroundTaskService service =
        BackgroundTaskService(shell: shell, maxRunningTasks: 2);
    final String id = await service.start('sleep 100');

    expect(service.kill(id), isTrue);
    expect(process.killed, isTrue);
    expect(service.list().single.status, ShellProcessStatus.killed);
    expect(
      () => service.output('bg-999'),
      throwsA(isA<BackgroundException>().having(
          (BackgroundException e) => e.code, 'code', 'not-found')),
    );
  });

  test('记录保留 maxRecords 条：只裁剪已结束的最旧记录，在跑任务不丢', () async {
    final FakeBackgroundShell shell = FakeBackgroundShell(<FakeShellProcess>[
      FakeShellProcess(),
      FakeShellProcess(),
      FakeShellProcess(),
    ]);
    final BackgroundTaskService service =
        BackgroundTaskService(shell: shell, maxRecords: 2);
    await service.start('a');
    await service.start('b');
    // 前两条已结束 → 第三条启动后裁剪掉它们。
    shell.processes[0].complete();
    shell.processes[1].complete();
    await service.start('c');
    await Future<void>.delayed(Duration.zero);

    expect(service.list().map((BackgroundTaskView v) => v.id),
        <String>['bg-2', 'bg-3']);
  });
}

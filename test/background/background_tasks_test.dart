/// BackgroundTaskService 退出语义：keep_alive_on_exit 决定 shutdown 杀或留。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'support/fake_shell.dart';

BackgroundTaskService _boot(
  List<FakeShellProcess> processes, {
  bool keepAliveOnExit = false,
}) => BackgroundTaskService(
  shell: FakeBackgroundShell(processes),
  keepAliveOnExit: keepAliveOnExit,
);

void main() {
  test('keepAliveOnExit=false：shutdown 终止所有在跑任务', () async {
    final BackgroundTaskService service = _boot(<FakeShellProcess>[
      FakeShellProcess(),
      FakeShellProcess(),
    ]);
    await service.start('a');
    await service.start('b');

    service.shutdown();

    for (final BackgroundTaskView task in service.list()) {
      expect(task.status, isNot(ShellProcessStatus.running));
    }
  });

  test('keepAliveOnExit=true：shutdown 不杀任务（detach）', () async {
    final FakeShellProcess process = FakeShellProcess();
    final BackgroundTaskService service = _boot(<FakeShellProcess>[
      process,
    ], keepAliveOnExit: true);
    await service.start('a');

    service.shutdown();

    expect(process.killed, isFalse);
    expect(service.list().single.status, ShellProcessStatus.running);
  });

  test('shutdown 幂等：重复调用安全', () async {
    final BackgroundTaskService service = _boot(<FakeShellProcess>[
      FakeShellProcess(),
    ]);
    await service.start('a');

    service.shutdown();
    service.shutdown();

    expect(service.list().single.status, isNot(ShellProcessStatus.running));
  });
}

/// FormatterService：成功路径、命令覆盖与多文件去重。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';

import 'support/format_harness.dart';

void main() {
  test('成功：dart format + 绝对路径 + 配置超时', () async {
    final Directory dir = createProject('svc-ok', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, FormatterService service) =
        bootFormatter(dir.path);
    addTearDown(app.dispose);

    expect(await service.runIfNeeded(<String>['lib/a.dart']), isNull);
    expect(shell.commands, hasLength(1));
    expect(
      shell.commands.single,
      "dart format '${absolutePath(dir, 'lib/a.dart')}'",
    );
    expect(shell.lastRequest!.workdir, dir.path);
    expect(shell.lastRequest!.timeoutMs, 10000);
  });

  test('enabled=false：不跑命令', () async {
    final Directory dir = createProject('svc-off', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, FormatterService service) =
        bootFormatter(dir.path, config: const FormatterConfig());
    addTearDown(app.dispose);

    expect(await service.runIfNeeded(<String>['lib/a.dart']), isNull);
    expect(shell.commands, isEmpty);
  });

  test(r'命令覆盖：$FILE 替换为绝对路径，extensions 限定范围', () async {
    final Directory dir = createProject('svc-override', <String, String>{
      'note.txt': 'x\n',
      'note.md': 'y\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (
      Context app,
      RecordingShell shell,
      FormatterService service,
    ) = bootFormatter(
      dir.path,
      config: const FormatterConfig(
        enabled: true,
        command: r'myfmt --check $FILE',
        extensions: <String>['.txt'],
      ),
    );
    addTearDown(app.dispose);

    expect(await service.runIfNeeded(<String>['note.txt']), isNull);
    expect(
      shell.commands.single,
      "myfmt --check '${absolutePath(dir, 'note.txt')}'",
    );

    // 扩展名不在白名单：不跑。
    expect(await service.runIfNeeded(<String>['note.md']), isNull);
    expect(shell.commands, hasLength(1));
  });

  test(r'命令覆盖无 $FILE：文件路径追加在末尾', () async {
    final Directory dir = createProject('svc-append', <String, String>{
      'note.txt': 'x\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (
      Context app,
      RecordingShell shell,
      FormatterService service,
    ) = bootFormatter(
      dir.path,
      config: const FormatterConfig(
        enabled: true,
        command: 'myfmt',
        extensions: <String>['.txt'],
      ),
    );
    addTearDown(app.dispose);

    expect(await service.runIfNeeded(<String>['note.txt']), isNull);
    expect(shell.commands.single, "myfmt '${absolutePath(dir, 'note.txt')}'");
  });

  test('多文件逐个格式化，同一路径只跑一次', () async {
    final Directory dir = createProject('svc-multi', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
      'lib/b.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, FormatterService service) =
        bootFormatter(dir.path);
    addTearDown(app.dispose);

    expect(
      await service.runIfNeeded(<String>[
        'lib/a.dart',
        'lib/a.dart',
        'lib/b.dart',
      ]),
      isNull,
    );
    expect(shell.commands, hasLength(2));
    expect(shell.commands[0], contains('a.dart'));
    expect(shell.commands[1], contains('b.dart'));
  });
}

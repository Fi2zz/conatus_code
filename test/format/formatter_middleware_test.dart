/// formatter 中间件：只处理成功的编辑工具、失败降级与待定补丁跳过。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'support/format_harness.dart';

ToolCall _write(String path) =>
    ToolCall(name: 'write_file', arguments: <String, Object?>{'path': path});

void main() {
  test('成功格式化：工具结果保持成功且不追加噪声', () async {
    final Directory dir = createProject('mw-ok', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, _) = bootFormatter(dir.path);
    addTearDown(app.dispose);
    registerWriteFile(app);

    final ToolResult result = await app.tools.call(_write('lib/a.dart'));
    expect(result.isError, isFalse);
    expect(result.content, '已写入');
    expect(shell.commands, hasLength(1));
  });

  test('格式化失败：工具仍成功，追加 [Formatter] skipped', () async {
    final Directory dir = createProject('mw-fail', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell _, _) = bootFormatter(
      dir.path,
      answer: (String _) => failureResult(stderr: '格式错误'),
    );
    addTearDown(app.dispose);
    registerWriteFile(app);

    final ToolResult result = await app.tools.call(_write('lib/a.dart'));
    expect(result.isError, isFalse);
    expect(result.content, contains('已写入'));
    expect(result.content, contains('[Formatter] skipped:'));
    expect(result.content, contains('格式错误'));
  });

  test('工具失败：不跑 formatter', () async {
    final Directory dir = createProject('mw-tool-fail', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, _) = bootFormatter(dir.path);
    addTearDown(app.dispose);
    registerWriteFile(
      app,
      result: () =>
          ToolResult.failure('写失败', error: const ToolError('FS_ERROR', '写失败')),
    );

    final ToolResult result = await app.tools.call(_write('lib/a.dart'));
    expect(result.isError, isTrue);
    expect(shell.commands, isEmpty);
  });

  test('非编辑工具：不跑 formatter', () async {
    final Directory dir = createProject('mw-other', <String, String>{
      'pubspec.yaml': 'name: x\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, _) = bootFormatter(dir.path);
    addTearDown(app.dispose);
    registerWriteFile(app);

    final ToolResult result = await app.tools.call(
      const ToolCall(name: 'get_time'),
    );
    expect(result.isError, isTrue); // 未注册的 get_time
    expect(shell.commands, isEmpty);
  });

  test('故事层待定补丁未落盘：跳过', () async {
    final Directory dir = createProject('mw-pending', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, _) = bootFormatter(dir.path);
    addTearDown(app.dispose);
    registerWriteFile(
      app,
      result: () =>
          ToolResult.success('编辑已登记为待定补丁 #1（1 个文件），待人审阅生效；无需重试，可继续其它工作。'),
    );

    await app.tools.call(_write('lib/a.dart'));
    expect(shell.commands, isEmpty);
  });

  test('apply_patch 多文件：逐文件各跑一次', () async {
    final Directory dir = createProject('mw-patch', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
      'lib/b.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, _) = bootFormatter(dir.path);
    addTearDown(app.dispose);
    registerApplyPatch(app, <String>['lib/a.dart', 'lib/b.dart']);

    final ToolResult result = await app.tools.call(
      const ToolCall(
        name: 'apply_patch',
        arguments: <String, Object?>{'patch': 'x'},
      ),
    );
    expect(result.isError, isFalse);
    expect(shell.commands, hasLength(2));
    expect(shell.commands[0], contains('a.dart'));
    expect(shell.commands[1], contains('b.dart'));
  });

  test('edit_file：成功结果同样触发格式化', () async {
    final Directory dir = createProject('mw-edit', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, _) = bootFormatter(dir.path);
    addTearDown(app.dispose);
    registerEditFile(app);

    final ToolResult result = await app.tools.call(
      const ToolCall(
        name: 'edit_file',
        arguments: <String, Object?>{'path': 'lib/a.dart'},
      ),
    );
    expect(result.isError, isFalse);
    expect(shell.commands, hasLength(1));
  });

  test('enabled=false：mount 为空 Disposer，不拦截', () async {
    final Directory dir = createProject('mw-off', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, FormatterService service) =
        bootFormatter(dir.path, config: const FormatterConfig());
    addTearDown(app.dispose);
    addTearDown(service.mount(app.tools));
    registerWriteFile(app);

    final ToolResult result = await app.tools.call(_write('lib/a.dart'));
    expect(result.isError, isFalse);
    expect(result.content, '已写入');
    expect(shell.commands, isEmpty);
  });
}

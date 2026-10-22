/// FormatterService：`.opencode`、已删除、越界与文件数上限等跳过条件。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';

import 'support/format_harness.dart';

void main() {
  test('跳过 .opencode/**', () async {
    final Directory dir = createProject('svc-opencode', <String, String>{
      'pubspec.yaml': 'name: x\n',
      '.opencode/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, FormatterService service) =
        bootFormatter(dir.path);
    addTearDown(app.dispose);

    expect(await service.runIfNeeded(<String>['.opencode/a.dart']), isNull);
    expect(shell.commands, isEmpty);
  });

  test('跳过已删除文件', () async {
    final Directory dir = createProject('svc-gone', <String, String>{
      'pubspec.yaml': 'name: x\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, FormatterService service) =
        bootFormatter(dir.path);
    addTearDown(app.dispose);

    expect(await service.runIfNeeded(<String>['lib/gone.dart']), isNull);
    expect(shell.commands, isEmpty);
  });

  test('跳过工作区之外的路径', () async {
    final Directory dir = createProject('svc-outside', <String, String>{
      'pubspec.yaml': 'name: x\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, FormatterService service) =
        bootFormatter(dir.path);
    addTearDown(app.dispose);

    expect(await service.runIfNeeded(<String>['../outside.dart']), isNull);
    expect(shell.commands, isEmpty);
  });

  test('超过 20 个文件时只格式化前 20 个并提示剩余', () async {
    final Directory dir = createProject('svc-cap', <String, String>{
      'pubspec.yaml': 'name: x\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final List<String> files = <String>[];
    for (int i = 0; i < kFormatterMaxFiles + 1; i++) {
      final String path = 'lib/f$i.dart';
      addFile(dir, path, 'void f$i() {}\n');
      files.add(path);
    }
    final (Context app, RecordingShell shell, FormatterService service) =
        bootFormatter(dir.path);
    addTearDown(app.dispose);

    final String? notice = await service.runIfNeeded(files);
    expect(notice, isNotNull);
    expect(notice, contains('另有 1 个未处理'));
    expect(shell.commands, hasLength(kFormatterMaxFiles));
  });

  test('无探针（无项目标记）→ 静默跳过', () async {
    final Directory dir = createProject('svc-noprobe', <String, String>{
      'a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell shell, FormatterService service) =
        bootFormatter(dir.path);
    addTearDown(app.dispose);

    expect(await service.runIfNeeded(<String>['a.dart']), isNull);
    expect(shell.commands, isEmpty);
  });
}

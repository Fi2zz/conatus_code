/// FormatterService：失败、超时、沙箱白名单拒绝都只降级为提示。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';

import 'support/format_harness.dart';

void main() {
  test('失败：追加 [Formatter] skipped 原因', () async {
    final Directory dir = createProject('svc-fail', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (
      Context app,
      RecordingShell _,
      FormatterService service,
    ) = bootFormatter(
      dir.path,
      answer: (String _) => failureResult(stderr: 'syntax error'),
    );
    addTearDown(app.dispose);

    final String? notice = await service.runIfNeeded(<String>['lib/a.dart']);
    expect(notice, contains('[Formatter] skipped:'));
    expect(notice, contains('syntax error'));
  });

  test('超时：降级为 skipped 且说明超时', () async {
    final Directory dir = createProject('svc-timeout', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (Context app, RecordingShell _, FormatterService service) =
        bootFormatter(dir.path, answer: (String _) => timeoutResult());
    addTearDown(app.dispose);

    final String? notice = await service.runIfNeeded(<String>['lib/a.dart']);
    expect(notice, contains('[Formatter] skipped:'));
    expect(notice, contains('超时'));
  });

  test('白名单拒绝（exitCode null）→ skipped 且带拒绝原因', () async {
    final Directory dir = createProject('svc-denied', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (
      Context app,
      RecordingShell _,
      FormatterService service,
    ) = bootFormatter(
      dir.path,
      answer: (String _) =>
          failureResult(exitCode: null, stderr: '可执行文件不在白名单：gofmt'),
    );
    addTearDown(app.dispose);

    final String? notice = await service.runIfNeeded(<String>['lib/a.dart']);
    expect(notice, contains('[Formatter] skipped:'));
    expect(notice, contains('白名单'));
  });

  test('执行器异常：不抛出，降级为 skipped', () async {
    final Directory dir = createProject('svc-throw', <String, String>{
      'pubspec.yaml': 'name: x\n',
      'lib/a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final (
      Context app,
      RecordingShell _,
      FormatterService service,
    ) = bootFormatter(
      dir.path,
      answer: (String _) => throw StateError('shell 不可用'),
    );
    addTearDown(app.dispose);

    final String? notice = await service.runIfNeeded(<String>['lib/a.dart']);
    expect(notice, contains('[Formatter] skipped:'));
    expect(notice, contains('shell 不可用'));
  });
}

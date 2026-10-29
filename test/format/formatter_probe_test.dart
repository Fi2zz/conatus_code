/// formatter 探针：按项目标记与扩展名探测。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

import 'support/format_harness.dart';

void main() {
  test('Dart：pubspec.yaml + .dart → dart format', () {
    final Directory dir = createProject('probe-dart', <String, String>{
      'pubspec.yaml': 'name: x\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    final FormatterProbe? probe = detectFormatter(dir.path, 'lib/a.dart');
    expect(probe, isNotNull);
    expect(probe!.name, 'dart');
    expect(probe.command, <String>['dart', 'format']);
    expect(probe.extensions, contains('.dart'));
    expect(detectFormatter(dir.path, 'lib/a.txt'), isNull);
  });

  test('Go：go.mod + .go → gofmt -w', () {
    final Directory dir = createProject('probe-go', <String, String>{
      'go.mod': 'module x\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    final FormatterProbe? probe = detectFormatter(dir.path, 'main.go');
    expect(probe!.name, 'go');
    expect(probe.command, <String>['gofmt', '-w']);
  });

  test('Rust：Cargo.toml + .rs → rustfmt', () {
    final Directory dir = createProject('probe-rust', <String, String>{
      'Cargo.toml': '[package]\nname = "x"\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    final FormatterProbe? probe = detectFormatter(dir.path, 'src/main.rs');
    expect(probe!.name, 'rust');
    expect(probe.command, <String>['rustfmt']);
  });

  test('Prettier：package.json 声明 prettier + .ts → prettier --write', () {
    final Directory dir = createProject('probe-prettier', <String, String>{
      'package.json': '{"devDependencies":{"prettier":"^3.0.0"}}',
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    final FormatterProbe? probe = detectFormatter(dir.path, 'src/a.ts');
    expect(probe!.name, 'prettier');
    expect(probe.command, <String>['prettier', '--write']);
    expect(probe.extensions, contains('.ts'));
  });

  test('Prettier：package.json 未声明 prettier → 不探测', () {
    final Directory dir = createProject('probe-no-prettier', <String, String>{
      'package.json': '{"dependencies":{"left-pad":"1.0.0"}}',
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    expect(detectFormatter(dir.path, 'src/a.ts'), isNull);
  });

  test('Ruff：pyproject 含 [tool.ruff] + .py → ruff format', () {
    final Directory dir = createProject('probe-ruff', <String, String>{
      'pyproject.toml': '[tool.ruff]\nline-length = 88\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    final FormatterProbe? probe = detectFormatter(dir.path, 'a.py');
    expect(probe!.name, 'ruff');
    expect(probe.command, <String>['ruff', 'format']);
    expect(detectFormatter(dir.path, 'a.txt'), isNull);
  });

  test('Ruff：ruff.toml 标记同样生效', () {
    final Directory dir = createProject('probe-ruff-toml', <String, String>{
      'ruff.toml': 'line-length = 88\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    expect(detectFormatter(dir.path, 'a.py')!.name, 'ruff');
  });

  test('无项目标记 → 不探测', () {
    final Directory dir = createProject('probe-none', <String, String>{
      'a.dart': 'void main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    expect(detectFormatter(dir.path, 'a.dart'), isNull);
  });

  test('跳过 .opencode/**（含嵌套目录）', () {
    final Directory dir = createProject('probe-opencode', <String, String>{
      'pubspec.yaml': 'name: x\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    expect(detectFormatter(dir.path, '.opencode/a.dart'), isNull);
    expect(detectFormatter(dir.path, 'src/.opencode/a.dart'), isNull);
  });

  test('跳过工作区之外（../ 或绝对路径）', () {
    final Directory dir = createProject('probe-outside', <String, String>{
      'pubspec.yaml': 'name: x\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    expect(detectFormatter(dir.path, '../a.dart'), isNull);
    expect(detectFormatter(dir.path, '/elsewhere/a.dart'), isNull);
  });
}

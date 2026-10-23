/// 边界：项目祖先层 / 工作目录内 / 嵌套的符号链接策略与无 git 回退。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

final String _sep = Platform.pathSeparator;

String _dir(String prefix) {
  final Directory dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir.path;
}

void _write(String base, List<String> parts, String content) {
  final String path = <String>[base, ...parts].join(_sep);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

InstructionLoader _loader(String workdir, String home) {
  final InstructionLoader loader = InstructionLoader(
    workdir: workdir,
    home: home,
  );
  addTearDown(loader.dispose);
  return loader;
}

void main() {
  test('workdir 是子目录时，项目祖先层的普通 AGENTS.md 仍加载', () async {
    final String repo = _dir('nava-guard-repo-');
    Directory('$repo$_sep.git').createSync();
    _write(repo, <String>['AGENTS.md'], 'ROOT-AGENTS');
    final String workdir = '$repo${_sep}pkg';
    Directory(workdir).createSync();

    expect(
      await _loader(workdir, _dir('nava-guard-home-')).compose(),
      contains('ROOT-AGENTS'),
    );
  });

  test('项目祖先层 AGENTS.md 是符号链接（仓库内越界）→ 跳过', () async {
    if (Platform.isWindows) return;
    final String repo = _dir('nava-guard-repo-');
    Directory('$repo$_sep.git').createSync();
    _write(repo, <String>['secret.md'], 'REPO-SECRET');
    Link('$repo${_sep}AGENTS.md').createSync('$repo${_sep}secret.md');
    _write(repo, <String>['NAVA.md'], 'ROOT-NAVA');
    final String workdir = '$repo${_sep}pkg';
    Directory(workdir).createSync();

    final String? text = await _loader(
      workdir,
      _dir('nava-guard-home-'),
    ).compose();

    expect(text, 'ROOT-NAVA');
    expect(text, isNot(contains('REPO-SECRET')));
  });

  test('workdir 内 AGENTS.md 指向工作区外（含仓库祖先）→ 跳过', () async {
    if (Platform.isWindows) return;
    final String repo = _dir('nava-guard-repo-');
    Directory('$repo$_sep.git').createSync();
    _write(repo, <String>['shared.md'], 'REPO-SHARED');
    final String workdir = '$repo${_sep}pkg';
    Directory(workdir).createSync();
    Link('$workdir${_sep}AGENTS.md').createSync('$repo${_sep}shared.md');

    expect(await _loader(workdir, _dir('nava-guard-home-')).compose(), isNull);
  });

  test('嵌套 AGENTS.md 指向工作区外 → 跳过且 notePath 返回 false', () async {
    if (Platform.isWindows) return;
    final String root = _dir('nava-guard-nested-');
    final String outside = _dir('nava-guard-out-');
    _write(outside, <String>['secret.md'], 'LEAKED');
    final String sub = '$root${_sep}sub';
    Directory(sub).createSync();
    Link('$sub${_sep}AGENTS.md').createSync('$outside${_sep}secret.md');
    final InstructionLoader loader = _loader(root, _dir('nava-guard-home-'));

    expect(await loader.notePath('$sub${_sep}a.dart'), isFalse);
    expect(await loader.compose(), isNull);
  });

  test('workdir 内符号链接指向工作区内 → 照读', () async {
    if (Platform.isWindows) return;
    final String root = _dir('nava-guard-inside-');
    _write(root, <String>['REAL.md'], 'REAL-INSIDE');
    Link('$root${_sep}AGENTS.md').createSync('$root${_sep}REAL.md');

    expect(
      await _loader(root, _dir('nava-guard-home-')).compose(),
      'REAL-INSIDE',
    );
  });

  test('无 git 时项目根退回家目录（workdir 在其内）', () async {
    final String home = _dir('nava-guard-home-');
    _write(home, <String>['AGENTS.md'], 'HOME-LEVEL');
    final String workdir = '$home${_sep}work';
    Directory(workdir).createSync();

    expect(await _loader(workdir, home).compose(), 'HOME-LEVEL');
  });
}

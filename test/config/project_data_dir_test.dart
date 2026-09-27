/// 项目数据目录解析：缺省落用户配置目录（不污染工作区），显式配置才落工作区。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  late Directory home;
  late Directory work;

  setUp(() {
    home = Directory.systemTemp.createTempSync('nava-home');
    work = Directory.systemTemp.createTempSync('nava-work');
    addTearDown(() {
      home.deleteSync(recursive: true);
      work.deleteSync(recursive: true);
    });
  });

  Map<String, String> env() => <String, String>{'HOME': home.path};

  test('缺省：用户配置目录 projects/<编码工作区>（工作区零写入）', () {
    final String dir = resolveProjectDataDir(workdir: work.path, env: env());

    final String expectedLeaf = Uri.encodeComponent(
      work.resolveSymbolicLinksSync(),
    );
    expect(dir, '${home.path}/.nava/projects/$expectedLeaf');
    expect(Directory(work.path).listSync(), isEmpty);
  });

  test('NAVA_HOME 优先于 HOME', () {
    final Directory custom = Directory.systemTemp.createTempSync('nava-x');
    addTearDown(() => custom.deleteSync(recursive: true));

    final String dir = resolveProjectDataDir(
      workdir: work.path,
      env: <String, String>{'HOME': home.path, 'NAVA_HOME': custom.path},
    );

    expect(dir, startsWith('${custom.path}/projects/'));
  });

  test('显式 project_dir：保持旧语义 <workdir>/<projectDir>', () {
    final String dir = resolveProjectDataDir(
      workdir: work.path,
      projectDir: '.state',
      env: env(),
    );

    expect(dir, '${work.path}/.state');
  });

  test('工作区路径规范化：尾斜杠/符号链接都解析到同一目录', () {
    final String withSlash = '${work.path}${Platform.pathSeparator}';
    final String a = resolveProjectDataDir(workdir: withSlash, env: env());
    final String b = resolveProjectDataDir(workdir: work.path, env: env());

    expect(a, b);
  });
}

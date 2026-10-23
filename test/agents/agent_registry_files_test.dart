/// Agent 文件加载：损坏隔离、扩展名、只读边界与读取失败提示。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

import 'agent_test_support.dart';

/// 非 root 的 Unix 用户才能用 chmod 制造不可读路径。
bool get canDenyRead =>
    !Platform.isWindows &&
    Process.runSync('id', <String>['-u']).stdout.toString().trim() != '0';

void main() {
  late Directory home;
  late Directory work;

  setUp(() {
    home = Directory.systemTemp.createTempSync('nava-agent-files-home');
    work = Directory.systemTemp.createTempSync('nava-agent-files-work');
    addTearDown(() {
      home.deleteSync(recursive: true);
      work.deleteSync(recursive: true);
    });
  });

  Future<AgentRegistry> load() =>
      AgentRegistry.load(workdir: work.path, home: home.path);

  test('无效文件跳过且其余 Agent 照常加载，并记录原因', () async {
    writeAgent(Directory('${work.path}/.nava/agents'), 'good.md', body: 'good');
    writeAgent(
      Directory('${work.path}/.nava/agents'),
      'bad.md',
      frontmatter: 'mode: helper',
      body: 'bad',
    );

    final AgentRegistry registry = await load();

    expect(registry.byId('good')!.system, 'good');
    expect(registry.byId('bad'), isNull);
    expect(registry.warnings, hasLength(1));
    expect(registry.warnings.single, contains('bad.md'));
    expect(registry.warnings.single, contains('mode'));
  });

  test('只发现 .md 文件（扩展名大小写不敏感）', () async {
    final Directory root = Directory('${work.path}/.nava/agents');
    writeAgent(root, 'yes.md', body: 'yes');
    writeAgent(root, 'upper.MD', body: 'upper');
    writeAgent(root, 'no.txt', body: 'no');

    final AgentRegistry registry = await load();

    expect(registry.byId('yes'), isNotNull);
    expect(registry.byId('upper'), isNotNull);
    expect(registry.byId('no'), isNull);
  });

  test('文件名首尾空白不进入 ID，byId 可直接命中', () async {
    writeAgent(
      Directory('${work.path}/.nava/agents'),
      ' spaced.md',
      body: 'spaced',
    );

    final AgentRegistry registry = await load();

    expect(registry.byId('spaced')!.system, 'spaced');
    expect(registry.byId(' spaced'), isNotNull);
  });

  test('干净加载没有警告', () async {
    writeAgent(
      Directory('${work.path}/.nava/agents'),
      'clean.md',
      frontmatter: 'mode: subagent',
    );

    final AgentRegistry registry = await load();

    expect(registry.warnings, isEmpty);
  });

  test('不可读文件记录警告并继续加载', () async {
    final Directory root = Directory('${work.path}/.nava/agents')
      ..createSync(recursive: true);
    final File locked = File('${root.path}/locked.md')
      ..writeAsStringSync('secret');
    Process.runSync('chmod', <String>['000', locked.path]);
    addTearDown(() => Process.runSync('chmod', <String>['600', locked.path]));
    writeAgent(root, 'ok.md', body: 'ok');

    final AgentRegistry registry = await load();

    expect(registry.byId('ok')!.system, 'ok');
    expect(registry.warnings.single, contains('locked.md'));
    expect(registry.warnings.single, contains('无法读取 Agent 文件'));
  }, skip: canDenyRead ? false : '需要非 root Unix 用户');

  test('不可读目录记录警告并继续加载', () async {
    final Directory locked = Directory('${work.path}/.nava/agents')
      ..createSync(recursive: true);
    Process.runSync('chmod', <String>['000', locked.path]);
    addTearDown(() => Process.runSync('chmod', <String>['700', locked.path]));

    final AgentRegistry registry = await load();

    expect(registry.warnings.single, contains('无法读取 Agent 目录'));
    expect(registry.byId('build'), isNotNull);
  }, skip: canDenyRead ? false : '需要非 root Unix 用户');

  test('加载不修改 .opencode（文件与内容保持不变）', () async {
    final Directory opencode = Directory('${work.path}/.opencode/agents');
    writeAgent(opencode, 'reviewer.md', body: 'review body');
    writeAgent(opencode, 'team/deep.md', body: 'deep body');
    final List<String> before = snapshotDirectory(opencode);

    await load();

    expect(snapshotDirectory(opencode), before);
  });
}

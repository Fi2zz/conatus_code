import 'dart:convert';
import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_harness/conatus_harness.dart';
import 'package:test/test.dart';

HarnessManifest _manifest(String name, {String effort = 'medium'}) =>
    HarnessManifest(
      name: name,
      profile: ExecutionProfile(
        name: 'standard',
        reasoningEffort: effort,
        budget: const ToolBudgetPolicy(),
      ),
      sections: const <PromptSectionSpec>[
        PromptSectionSpec(name: 'guide', text: '先读后写。'),
      ],
    );

File _write(Directory dir, String fileName, HarnessManifest manifest) {
  final File file = File('${dir.path}/$fileName');
  file.writeAsStringSync(jsonEncode(manifest.toJson()));
  return file;
}

Future<int> _run(List<String> args, StringBuffer out, StringBuffer err) =>
    runHarnessCommand(args, out: out, err: err);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('nava-harness-'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('无参数打印用法并返回 2', () async {
    final StringBuffer out = StringBuffer();
    final int code = await _run(const <String>[], out, StringBuffer());

    expect(code, 2);
    expect(out.toString(), contains('nava harness'));
  });

  test('list 列出目录下的 manifest 摘要', () async {
    _write(dir, 'a.json', _manifest('alpha'));
    _write(dir, 'b.json', _manifest('beta', effort: 'low'));
    final StringBuffer out = StringBuffer();

    final int code = await _run(
      <String>['list', dir.path],
      out,
      StringBuffer(),
    );

    expect(code, 0);
    expect(out.toString(), contains('alpha'));
    expect(out.toString(), contains('beta'));
    expect(out.toString(), contains('effort=low'));
  });

  test('list 目录不存在返回 2', () async {
    final StringBuffer err = StringBuffer();
    final int code = await _run(
      <String>['list', '${dir.path}/missing'],
      StringBuffer(),
      err,
    );

    expect(code, 2);
    expect(err.toString(), contains('目录不存在'));
  });

  test('list 遇到坏文件报错但仍列出好文件', () async {
    _write(dir, 'good.json', _manifest('good'));
    File('${dir.path}/bad.json').writeAsStringSync('{');
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();

    final int code = await _run(<String>['list', dir.path], out, err);

    expect(code, 2);
    expect(out.toString(), contains('good'));
    expect(err.toString(), contains('JSON 解析失败'));
  });

  test('show 输出规范化 JSON', () async {
    final File file = _write(dir, 'a.json', _manifest('alpha'));
    final StringBuffer out = StringBuffer();

    final int code = await _run(
      <String>['show', file.path],
      out,
      StringBuffer(),
    );

    expect(code, 0);
    final Map<String, Object?> parsed =
        jsonDecode(out.toString()) as Map<String, Object?>;
    expect(parsed['name'], 'alpha');
    expect(out.toString(), contains('"sections"'));
  });

  test('diff 输出差异行，相同则报无差异', () async {
    final File a = _write(dir, 'a.json', _manifest('base'));
    final File b = _write(dir, 'b.json', _manifest('heavy', effort: 'high'));
    final StringBuffer out = StringBuffer();

    expect(
      await _run(<String>['diff', a.path, b.path], out, StringBuffer()),
      0,
    );
    expect(out.toString(), contains('name: base → heavy'));
    expect(out.toString(), contains('profile.reasoningEffort: medium → high'));

    out.clear();
    expect(
      await _run(<String>['diff', a.path, a.path], out, StringBuffer()),
      0,
    );
    expect(out.toString(), contains('无差异'));
  });

  test('check 成功打印摘要，坏 JSON 返回 2', () async {
    final File good = _write(dir, 'a.json', _manifest('alpha'));
    final StringBuffer out = StringBuffer();

    expect(await _run(<String>['check', good.path], out, StringBuffer()), 0);
    expect(out.toString(), contains('OK alpha'));

    final File bad = File('${dir.path}/bad.json')..writeAsStringSync('[]');
    final StringBuffer err = StringBuffer();
    expect(await _run(<String>['check', bad.path], StringBuffer(), err), 2);
    expect(err.toString(), contains('顶层必须是 JSON 对象'));
  });

  test('未知子命令返回 2', () async {
    final StringBuffer err = StringBuffer();

    expect(await _run(<String>['nope'], StringBuffer(), err), 2);
    expect(err.toString(), contains('未知子命令'));
  });
}

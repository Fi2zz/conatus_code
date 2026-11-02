/// 项目插件发现：目录、opencode.json(c)、指纹。
library;

import 'dart:io';

import 'package:conatus_code/src/plugins/plugin_discovery.dart';
import 'package:conatus_code/src/plugins/plugin_entry.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-plugin-discovery');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('发现 .opencode/plugins 下的 JS 文件与目录', () async {
    final Directory plugins = Directory('${dir.path}/.opencode/plugins');
    plugins.createSync(recursive: true);
    File('${plugins.path}/one.mjs').writeAsStringSync('export default {};');
    final Directory two = Directory('${plugins.path}/two')..createSync();
    File('${two.path}/index.js').writeAsStringSync('export default {};');
    File('${two.path}/package.json').writeAsStringSync('{"main":"index.js"}');

    final result = await PluginDiscovery(workdir: dir.path).discoverProject();
    expect(result.candidates.length, 2);
    expect(result.candidates.every((c) => c.spec.projectScoped), isTrue);
    expect(
      result.candidates.map((c) => c.entry),
      contains(endsWith('one.mjs')),
    );
  });

  test('opencode.json 的 plugins 字符串与对象', () async {
    File('${dir.path}/opencode.json').writeAsStringSync('''
{
  // comment
  "plugins": [
    "./local-plugin",
    {"package": "@acme/plugin", "options": {"x": 1}}
  ]
}
''');
    final Directory local = Directory('${dir.path}/local-plugin')..createSync();
    File('${local.path}/index.js').writeAsStringSync('export default {};');

    final result = await PluginDiscovery(workdir: dir.path).discoverProject();
    expect(result.candidates.length, 2);
    final localCandidate = result.candidates.firstWhere((c) => c.local);
    expect(localCandidate.entry, endsWith('local-plugin/index.js'));
    final packageCandidate = result.candidates.firstWhere((c) => !c.local);
    expect(packageCandidate.entry, '@acme/plugin');
    expect(packageCandidate.spec.options['x'], 1);
  });

  test('忽略 .ts 并给出告警', () async {
    final Directory plugins = Directory('${dir.path}/.opencode/plugins')
      ..createSync(recursive: true);
    File('${plugins.path}/typed.ts').writeAsStringSync('export {};');
    final result = await PluginDiscovery(workdir: dir.path).discoverProject();
    expect(result.candidates, isEmpty);
    expect(result.warnings.join(), contains('TypeScript'));
  });

  test('指纹随内容变化', () async {
    final File entry = File('${dir.path}/index.js');
    entry.writeAsStringSync('export default { version: 1 };');
    final first = localPluginCandidate(entry.path);
    entry.writeAsStringSync('export default { version: 2 };');
    final second = localPluginCandidate(entry.path);
    expect(first.fingerprint, isNot(second.fingerprint));
  });
}

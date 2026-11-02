/// 插件配置解析与 TOML 片段。
library;

import 'dart:io';

import 'package:conatus_code/src/config/config_loader.dart';
import 'package:conatus_code/src/plugins/plugin_config.dart';
import 'package:conatus_code/src/plugins/plugin_toml_edit.dart';
import 'package:conatus_code/src/plugins/plugin_types.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-plugin-config');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('[[plugins]] 解析 source / enabled / options', () {
    final File file = File('${dir.path}/config.toml');
    file.writeAsStringSync('''
[[plugins]]
source = "superpowers@git+https://example.com/superpowers.git"
options = { agent = "reviewer", strict = true }

[[plugins]]
source = "./local"
enabled = false
''');
    final config = loadConfig(path: file.path);
    expect(config.plugins.length, 2);
    expect(config.plugins.first.source, contains('superpowers'));
    expect(config.plugins.first.options['agent'], 'reviewer');
    expect(config.plugins.last.enabled, isFalse);
  });

  test('缺少 source 报配置错误', () {
    final File file = File('${dir.path}/config.toml');
    file.writeAsStringSync('[[plugins]]\nenabled = true\n');
    expect(() => loadConfig(path: file.path), throwsA(isA<ConfigException>()));
  });

  test('pluginTomlSnippet 可被 TOML 重新解析', () {
    final String snippet = pluginTomlSnippet(
      './local',
      options: <String, Object?>{'agent': 'reviewer'},
    );
    final File file = File('${dir.path}/config.toml');
    file.writeAsStringSync('$snippet\n');
    final config = loadConfig(path: file.path);
    expect(config.plugins.single.source, './local');
    expect(config.plugins.single.options['agent'], 'reviewer');
  });

  test('removePluginBlock 只删匹配的块', () {
    const String toml = '''
# keep
[[plugins]]
source = "a"

[[plugins]]
source = "b"
enabled = false
''';
    final String result = removePluginBlock(toml, 'a');
    expect(result, isNot(contains('source = "a"')));
    expect(result, contains('[[plugins]]'));
    expect(result, contains('source = "b"'));
    expect(result, contains('# keep'));
  });

  test('pluginIdFor 稳定且带 source 末段', () {
    final String id = pluginIdFor('/tmp/my-plugin');
    expect(id, startsWith('my-plugin-'));
    expect(pluginIdFor('/tmp/my-plugin'), id);
    expect(pluginIdFor('/tmp/other'), isNot(id));
  });
}

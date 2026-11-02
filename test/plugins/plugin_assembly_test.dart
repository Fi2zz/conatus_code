/// 装配：项目发现 + 信任 + 工具注册 + headless 拒绝。
library;

import 'dart:io';

import 'package:conatus_code/src/config/config_schema.dart';
import 'package:conatus_code/src/plugins/plugin_assembly.dart';
import 'package:conatus_code/src/plugins/plugin_service.dart';
import 'package:conatus_code/src/plugins/plugin_trust.dart';
import 'package:conatus_code/src/plugins/plugin_types.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  late Directory home;
  late Directory work;

  setUp(() {
    home = Directory.systemTemp.createTempSync('nava-plugin-assembly');
    work = Directory.systemTemp.createTempSync('nava-plugin-assembly-work');
    final Directory plugins = Directory('${work.path}/.opencode/plugins')
      ..createSync(recursive: true);
    final String source =
        '${Directory.current.path}/test/plugins/fixtures/v1_plugin.js';
    File(source).copySync('${plugins.path}/v1_plugin.js');
    // 复制技能目录，保持 fixture 的相对路径。
    final Directory skills = Directory('${plugins.path}/skills')
      ..createSync(recursive: true);
    Directory(
      '${Directory.current.path}/test/plugins/fixtures/skills',
    ).listSync(recursive: true).whereType<File>().forEach((File file) {
      final String rel = file.path.split('/fixtures/skills/').last;
      final File target = File('${skills.path}/$rel');
      target.parent.createSync(recursive: true);
      file.copySync(target.path);
    });
  });

  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  test('交互审批 allowOnce：注册插件工具与技能根', () async {
    final ToolRegistry tools = ToolRegistry();
    final PluginService service = await PluginAssembly.assemble(
      plugins: const [],
      workdir: work.path,
      baseDir: work.path,
      tools: tools,
      interactive: true,
      prompter: (List<PluginCandidate> items) async =>
          PluginTrustDecision.allowOnce,
      homeDir: home.path,
      warn: (String message) {},
    );
    expect(service.available, isTrue);
    expect(tools.names, contains('plugin_echo'));
    expect(service.skillRoots, isNotEmpty);
    expect(service.shellEnv['TEST_PLUGIN_ENV'], '1');
    await service.close();
  });

  test('headless 默认拒绝项目插件，但显式配置的全局插件仍加载', () async {
    final ToolRegistry tools = ToolRegistry();
    final String fixture =
        '${Directory.current.path}/test/plugins/fixtures/v1_plugin.js';
    final PluginService service = await PluginAssembly.assemble(
      plugins: <PluginConfig>[PluginConfig(source: fixture)],
      workdir: work.path,
      baseDir: work.path,
      tools: tools,
      interactive: false,
      homeDir: home.path,
      warn: (String message) {},
    );
    expect(service.available, isTrue);
    expect(tools.names, contains('plugin_echo'));
    await service.close();
  });
}

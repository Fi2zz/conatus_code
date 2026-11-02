/// Node 宿主端到端：V1/V2 插件、工具、hook、事件与环境变量。
library;

import 'dart:io';

import 'package:conatus_code/src/plugins/plugin_entry.dart';
import 'package:conatus_code/src/plugins/plugin_host.dart';
import 'package:conatus_code/src/plugins/plugin_types.dart';
import 'package:test/test.dart';

void main() {
  late String? node;
  late Directory home;
  late Directory work;

  setUpAll(() async {
    node = await PluginHost.resolveNode();
  });

  setUp(() {
    home = Directory.systemTemp.createTempSync('nava-plugin-host');
    work = Directory.systemTemp.createTempSync('nava-plugin-work');
  });

  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  test('V1 插件：技能根、工具、before/after、event、shell.env', () async {
    if (node == null) return;
    final String fixture =
        '${Directory.current.path}/test/plugins/fixtures/v1_plugin.js';
    final PluginHost host = PluginHost(
      node: node!,
      scriptPath: await PluginHost.ensureHostScript(homeDir: home.path),
      candidates: <PluginCandidate>[
        localPluginCandidate(fixture, projectScoped: true),
      ],
      workdir: work.path,
    );
    final PluginInitResult result = await host.start();
    expect(result.skillRoots.any((String p) => p.endsWith('skills')), isTrue);
    expect(result.tools.map((t) => t.name), contains('plugin_echo'));
    expect(result.shellEnv['TEST_PLUGIN_ENV'], '1');

    final Map<String, Object?> blocked = await host.hook(
      'tool.execute.before',
      input: <String, Object?>{'tool': 'read'},
      output: <String, Object?>{
        'args': <String, Object?>{'filePath': '.env'},
      },
    );
    expect(blocked['blocked'], isTrue);

    final Map<String, Object?> after = await host.hook(
      'tool.execute.after',
      input: <String, Object?>{'tool': 'read'},
      output: <String, Object?>{'output': 'body'},
    );
    expect((after['output'] as Map)['output'], contains('[after]'));

    expect(
      await host.executeTool('plugin_echo', <String, Object?>{'text': 'hi'}),
      'echo:hi',
    );

    host.notifyEvent('session.idle', <String, Object?>{'sessionID': 's'});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(File('${work.path}/plugin-event.txt').readAsStringSync(), 'idle');
    await host.close();
  });

  test('V2 插件：skill.transform 与 session context hook', () async {
    if (node == null) return;
    final String fixture =
        '${Directory.current.path}/test/plugins/fixtures/v2_plugin.js';
    final PluginHost host = PluginHost(
      node: node!,
      scriptPath: await PluginHost.ensureHostScript(homeDir: home.path),
      candidates: <PluginCandidate>[
        localPluginCandidate(fixture, projectScoped: true),
      ],
      workdir: work.path,
    );
    final PluginInitResult result = await host.start();
    expect(result.skills.map((s) => s.name), contains('plugin-skill'));
    expect(result.context, contains('PLUGIN CONTEXT'));
    await host.close();
  });
}

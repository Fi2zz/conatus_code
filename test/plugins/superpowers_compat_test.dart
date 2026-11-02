/// 真实 superpowers 插件兼容性（本机有缓存时运行）。
library;

import 'dart:io';

import 'package:conatus_code/src/plugins/plugin_entry.dart';
import 'package:conatus_code/src/plugins/plugin_host.dart';
import 'package:conatus_code/src/plugins/plugin_types.dart';
import 'package:test/test.dart';

String? _findSuperpowers() {
  final String home = Platform.environment['HOME'] ?? '';
  final Directory cache = Directory('$home/.cache/opencode/npm');
  if (!cache.existsSync()) return null;
  for (final FileSystemEntity entity in cache.listSync(recursive: true)) {
    if (entity is File &&
        entity.path.endsWith('/superpowers/index.js') &&
        entity.path.contains('node_modules')) {
      return entity.path;
    }
  }
  return null;
}

void main() {
  test('superpowers：技能与 bootstrap 上下文', () async {
    final String? entry = _findSuperpowers();
    if (entry == null) return;
    final String? node = await PluginHost.resolveNode();
    if (node == null) return;
    final Directory home = Directory.systemTemp.createTempSync(
      'nava-superpowers',
    );
    final Directory work = Directory.systemTemp.createTempSync(
      'nava-superpowers-work',
    );
    addTearDown(() {
      if (home.existsSync()) home.deleteSync(recursive: true);
      if (work.existsSync()) work.deleteSync(recursive: true);
    });
    final PluginHost host = PluginHost(
      node: node,
      scriptPath: await PluginHost.ensureHostScript(homeDir: home.path),
      candidates: <PluginCandidate>[
        localPluginCandidate(entry, projectScoped: true),
      ],
      workdir: work.path,
    );
    final PluginInitResult result = await host.start();
    expect(result.skills.map((s) => s.name), contains('using-superpowers'));
    expect(result.context, contains('EXTREMELY_IMPORTANT'));
    await host.close();
  });
}

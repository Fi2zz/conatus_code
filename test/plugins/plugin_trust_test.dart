/// 项目插件信任：审批、持久化与指纹失效。
library;

import 'dart:io';

import 'package:conatus_code/src/plugins/plugin_trust.dart';
import 'package:conatus_code/src/plugins/plugin_types.dart';
import 'package:test/test.dart';

PluginCandidate _candidate(String id, String fingerprint) => PluginCandidate(
  spec: PluginSpec(id: id, source: '/tmp/$id', projectScoped: true),
  origin: 'project-plugins',
  entry: '/tmp/$id',
  fingerprint: fingerprint,
);

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-plugin-trust');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('autoTrust 直接通过，autoDeny 直接拒绝', () async {
    final List<PluginCandidate> items = <PluginCandidate>[_candidate('a', '1')];
    expect(
      await PluginTrustStore(
        path: '${dir.path}/t.json',
        autoTrust: true,
      ).filter(items),
      items,
    );
    expect(
      await PluginTrustStore(
        path: '${dir.path}/t.json',
        autoDeny: true,
      ).filter(items),
      isEmpty,
    );
  });

  test('allowAlways 持久化后不再询问', () async {
    int calls = 0;
    final PluginTrustStore store = PluginTrustStore(
      path: '${dir.path}/t.json',
      prompter: (List<PluginCandidate> items) async {
        calls++;
        return PluginTrustDecision.allowAlways;
      },
    );
    final List<PluginCandidate> first = await store.filter(<PluginCandidate>[
      _candidate('a', '1'),
    ]);
    expect(first.length, 1);
    expect(calls, 1);
    final List<PluginCandidate> second = await store.filter(<PluginCandidate>[
      _candidate('a', '1'),
    ]);
    expect(second.length, 1);
    expect(calls, 1);
    expect(File('${dir.path}/t.json').existsSync(), isTrue);
  });

  test('指纹变化会重新询问', () async {
    int calls = 0;
    final PluginTrustStore store = PluginTrustStore(
      path: '${dir.path}/t.json',
      prompter: (List<PluginCandidate> items) async {
        calls++;
        return PluginTrustDecision.allowOnce;
      },
    );
    await store.filter(<PluginCandidate>[_candidate('a', '1')]);
    await store.filter(<PluginCandidate>[_candidate('a', '2')]);
    expect(calls, 2);
  });

  test('deny 只保留已信任项', () async {
    final PluginTrustStore store = PluginTrustStore(
      path: '${dir.path}/t.json',
      prompter: (List<PluginCandidate> items) async => PluginTrustDecision.deny,
    );
    expect(
      await store.filter(<PluginCandidate>[_candidate('a', '1')]),
      isEmpty,
    );
  });
}

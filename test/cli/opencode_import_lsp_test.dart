/// OpenCode `lsp` 导入映射与 TOML 渲染。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';
import 'package:toml/toml.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-import-lsp');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

OpenCodeImport _build(
  List<Map<String, Object?>> docs, {
  String workdir = '.',
}) =>
    buildOpenCodeImport(
      OpenCodeSources(
        documents: <OpenCodeDocument>[
          for (int index = 0; index < docs.length; index++)
            OpenCodeDocument(
              path: '/tmp/opencode-$index.jsonc',
              values: docs[index],
            ),
        ],
        warnings: const <String>[],
        workdir: workdir,
      ),
    );

void main() {
  test('lsp=false 关闭，object 映射 command/extensions/env/initialization', () {
    final OpenCodeImport disabled = _build(<Map<String, Object?>>[
      <String, Object?>{'lsp': false},
    ]);
    expect(disabled.lsp.enabled, isFalse);
    expect(disabled.lsp.servers, isEmpty);

    final OpenCodeImport mapped = _build(<Map<String, Object?>>[
      <String, Object?>{
        'lsp': <String, Object?>{
          'custom': <String, Object?>{
            'command': <String>['custom-lsp', '--stdio'],
            'extensions': <String>['custom'],
            'env': <String, String>{'DEBUG': '1'},
            'initialization': <String, Object?>{'trace': 'verbose'},
          },
        },
      },
    ]);
    final LspServerConfig server = mapped.lsp.servers.single;
    expect(mapped.lsp.enabled, isTrue);
    expect(server.name, 'custom');
    expect(server.command, <String>['custom-lsp', '--stdio']);
    expect(server.extensions, <String>['.custom']);
    expect(server.env, <String, String>{'DEBUG': '1'});
    expect(server.initialization, <String, Object?>{'trace': 'verbose'});
  });

  test('lsp=true 只在 Dart 项目里生成 dart server', () {
    final Directory dart = _tempDir();
    File('${dart.path}/pubspec.yaml').writeAsStringSync('name: demo');
    final OpenCodeImport enabled = _build(
      <Map<String, Object?>>[
        <String, Object?>{'lsp': true},
      ],
      workdir: dart.path,
    );
    expect(enabled.lsp.enabled, isTrue);
    expect(enabled.lsp.servers.single.name, 'dart');
    expect(enabled.lsp.servers.single.extensions, <String>['.dart']);

    final Directory other = _tempDir();
    final OpenCodeImport skipped = _build(
      <Map<String, Object?>>[
        <String, Object?>{'lsp': true},
      ],
      workdir: other.path,
    );
    expect(skipped.lsp.enabled, isFalse);
    expect(skipped.warnings.join('\n'), contains('pubspec.yaml'));
  });

  test('计划写出可解析的 [lsp]，已有 [lsp] 时跳过', () {
    const OpenCodeImport imported = OpenCodeImport(
      lsp: LspConfig(
        enabled: true,
        servers: <LspServerConfig>[
          LspServerConfig(
            name: 'custom',
            command: <String>['custom-lsp', '--stdio'],
            extensions: <String>['.custom'],
          ),
        ],
      ),
    );
    final OpenCodeImportPlan plan = planOpenCodeImport(
      toml: '',
      import: imported,
    );

    expect(plan.updatedToml, contains('[lsp]'));
    expect(plan.updatedToml, contains('[lsp.servers.custom]'));
    expect(() => TomlDocument.parse(plan.updatedToml).toMap(), returnsNormally);

    final OpenCodeImportPlan skipped = planOpenCodeImport(
      toml: '[lsp]\nenabled = false\n',
      import: imported,
    );
    expect(skipped.added, isNot(contains('lsp')));
    expect(skipped.skipped.join('\n'), contains('[lsp]'));
  });
}

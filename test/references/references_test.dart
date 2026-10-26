/// references：路径解析、只读提示段与转义。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  test('resolveReferences：相对路径 / ~ / 缺失目录', () {
    final Directory work = Directory.systemTemp.createTempSync('nava-ref-work-');
    final Directory docs = Directory('${work.path}/docs')..createSync();
    final Directory home = Directory.systemTemp.createTempSync('nava-ref-home-');
    addTearDown(() {
      work.deleteSync(recursive: true);
      home.deleteSync(recursive: true);
    });
    final List<String> warnings = <String>[];

    final List<ResolvedReference> resolved = resolveReferences(
      <ReferenceConfig>[
        const ReferenceConfig(name: 'docs', path: 'docs', description: '产品文档'),
        ReferenceConfig(name: 'home', path: home.path),
        const ReferenceConfig(name: 'missing', path: 'nope'),
      ],
      workdir: work.path,
      onWarning: warnings.add,
    );

    expect(resolved, hasLength(2));
    expect(resolved[0].path, docs.resolveSymbolicLinksSync());
    expect(resolved[0].description, '产品文档');
    expect(warnings.single, contains('missing'));
  });

  test('renderReferences：列出别名、绝对路径并转义', () {
    final String text = renderReferences(const <ResolvedReference>[
      ResolvedReference(
        name: 'docs',
        path: '/tmp/<docs>',
        description: 'a & b',
      ),
    ]);

    expect(text, startsWith('<references>'));
    expect(text, contains('- docs: /tmp/&lt;docs&gt;'));
    expect(text, contains('a &amp; b'));
    expect(text, contains('read-only'));
  });
}

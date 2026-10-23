/// 命令解析的附加契约：名称规范化与可诊断的失败原因。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  test('名称去掉首尾空白', () {
    final CommandDefinition def = parseCommandDocument(
      'body',
      name: '  padded  ',
      sourcePath: '/tmp/padded.md',
    )!;

    expect(def.name, 'padded');
  });

  test('详细解析区分字段类型与 frontmatter 错误', () {
    final CommandParseResult typeError = parseCommandDocumentDetailed(
      '''
---
agent: 7
---
body
''',
      name: 'bad',
      sourcePath: '/tmp/bad.md',
    );
    final CommandParseResult yamlError = parseCommandDocumentDetailed(
      '''
---
description: [unclosed
---
body
''',
      name: 'bad',
      sourcePath: '/tmp/bad.md',
    );

    expect(typeError.definition, isNull);
    expect(typeError.error, contains('agent'));
    expect(typeError.error, contains('字符串'));
    expect(yamlError.definition, isNull);
    expect(yamlError.error, contains('frontmatter'));
  });
}

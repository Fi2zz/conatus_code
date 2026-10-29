/// JSONC 解码：注释、字符串内注释符与尾随逗号。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  test('去掉行注释与块注释', () {
    const String source = '''
{
  // 行注释
  "model": "anthropic/claude", /* 块注释 */
  "default_agent": "build"
}
''';

    expect(decodeJsonc(source), <String, Object?>{
      'model': 'anthropic/claude',
      'default_agent': 'build',
    });
  });

  test('字符串里的 // 与 /* 原样保留', () {
    const String source = '''
{
  "url": "https://example.com//a",
  "glob": "src/**/*.dart",
  "note": "/* not a comment */"
}
''';

    expect(decodeJsonc(source), <String, Object?>{
      'url': 'https://example.com//a',
      'glob': 'src/**/*.dart',
      'note': '/* not a comment */',
    });
  });

  test('去掉对象与数组的尾随逗号', () {
    const String source = '''
{
  "permissions": [
    { "action": "bash", "resource": "*", "effect": "ask" },
  ],
  "instructions": ["AGENTS.md",],
}
''';

    expect(decodeJsonc(source), <String, Object?>{
      'permissions': <Object?>[
        <String, Object?>{
          'action': 'bash',
          'resource': '*',
          'effect': 'ask',
        },
      ],
      'instructions': <Object?>['AGENTS.md'],
    });
  });

  test('字符串里的转义引号不误判注释或逗号', () {
    const String source = r'''
{
  "note": "quote \" and // and , }",
}
''';

    expect(decodeJsonc(source), <String, Object?>{
      'note': 'quote " and // and , }',
    });
  });
}

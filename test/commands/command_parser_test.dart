/// 命令文档解析：frontmatter 字段校验 + 正文模板。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  test('解析 frontmatter 与正文', () {
    final CommandDefinition def = parseCommandDocument(
      '''
---
description: review
agent: plan
model: ark/doubao-seed-2-0-lite
subagent: false
---
Review \$ARGUMENTS.
''',
      name: 'review',
      sourcePath: '/tmp/review.md',
    )!;

    expect(def.name, 'review');
    expect(def.description, 'review');
    expect(def.agent, 'plan');
    expect(def.model, 'ark/doubao-seed-2-0-lite');
    expect(def.subagent, false);
    expect(def.template, contains(r'$ARGUMENTS'));
    expect(def.sourcePath, '/tmp/review.md');
    expect(def.executor, isNull);
  });

  test('字段全部缺省时使用空描述、空 agent/model、非 subagent', () {
    final CommandDefinition def = parseCommandDocument(
      '''
---
---
hello
''',
      name: 'hello',
      sourcePath: '/tmp/hello.md',
    )!;

    expect(def.description, '');
    expect(def.agent, isNull);
    expect(def.model, isNull);
    expect(def.subagent, false);
    expect(def.template, 'hello');
  });

  test('允许空正文', () {
    final CommandDefinition def = parseCommandDocument(
      '''
---
description: empty
---
''',
      name: 'empty',
      sourcePath: '/tmp/empty.md',
    )!;

    expect(def.template, '');
  });

  test('无 frontmatter 时整篇正文作为模板', () {
    final CommandDefinition def = parseCommandDocument(
      'just a prompt',
      name: 'plain',
      sourcePath: '/tmp/plain.md',
    )!;

    expect(def.template, 'just a prompt');
    expect(def.description, '');
    expect(def.agent, isNull);
  });

  test('未知字段忽略', () {
    final CommandDefinition def = parseCommandDocument(
      '''
---
description: x
unknown: y
---
body
''',
      name: 'x',
      sourcePath: '/tmp/x.md',
    )!;

    expect(def.description, 'x');
  });

  test('字段类型错误时返回 null', () {
    expect(
      parseCommandDocument(
        '''
---
agent: 7
---
body
''',
        name: 'bad',
        sourcePath: '/tmp/bad.md',
      ),
      isNull,
    );
    expect(
      parseCommandDocument(
        '''
---
subagent: yes-please
---
body
''',
        name: 'bad',
        sourcePath: '/tmp/bad.md',
      ),
      isNull,
    );
  });

  test('frontmatter YAML 非法时返回 null', () {
    expect(
      parseCommandDocument(
        '''
---
description: [unclosed
---
body
''',
        name: 'bad',
        sourcePath: '/tmp/bad.md',
      ),
      isNull,
    );
  });

  test('缺少闭合围栏时返回 null', () {
    expect(
      parseCommandDocument(
        '''
---
description: x
body
''',
        name: 'bad',
        sourcePath: '/tmp/bad.md',
      ),
      isNull,
    );
  });

  test('空名称返回 null', () {
    expect(
      parseCommandDocument('body', name: '  ', sourcePath: '/tmp/x.md'),
      isNull,
    );
  });

  test('subagent 支持 true', () {
    final CommandDefinition def = parseCommandDocument(
      '''
---
subagent: true
---
body
''',
      name: 'sub',
      sourcePath: '/tmp/sub.md',
    )!;

    expect(def.subagent, true);
  });
}

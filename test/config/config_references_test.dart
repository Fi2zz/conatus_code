/// `[references.*]` 配置解析。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-ref-cfg-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}${Platform.pathSeparator}config.toml');
  file.writeAsStringSync(content);
  return file.path;
}

void main() {
  test('解析本地 reference', () {
    final ConatusCodeConfig config = loadConfig(path: _writeToml('''
[references.docs]
path = "../product-docs"
description = "产品文档"
'''));
    final ReferenceConfig reference = config.references.single;
    expect(reference.name, 'docs');
    expect(reference.path, '../product-docs');
    expect(reference.description, '产品文档');
  });

  test('git reference 与缺 path 抛错', () {
    expect(
      () => loadConfig(path: _writeToml('''
[references.remote]
repository = "acme/docs"
''')),
      throwsA(isA<ConfigException>().having(
        (ConfigException e) => e.message,
        'message',
        contains('git 引用暂不支持'),
      )),
    );
    expect(
      () => loadConfig(path: _writeToml('''
[references.bad]
description = "x"
''')),
      throwsA(isA<ConfigException>().having(
        (ConfigException e) => e.message,
        'message',
        contains('path 不能为空'),
      )),
    );
  });
}

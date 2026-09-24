/// `[hooks]` 表解析测试。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-hooks-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}${Platform.pathSeparator}$kConfigFileName');
  file.writeAsStringSync(content);
  return file.path;
}

void main() {
  test('缺省：三个事件都为空', () {
    final ConatusCodeConfig config = loadConfig(path: _writeToml('[agent]\n'));
    expect(config.hooks.preToolUse, isEmpty);
    expect(config.hooks.postToolUse, isEmpty);
    expect(config.hooks.stop, isEmpty);
  });

  test('完整解析', () {
    final ConatusCodeConfig config = loadConfig(path: _writeToml('''
[hooks]
pre_tool_use = ["echo pre > /tmp/x"]
post_tool_use = ["/usr/bin/true"]
stop = ["echo stop"]
'''));
    expect(config.hooks.preToolUse, <String>['echo pre > /tmp/x']);
    expect(config.hooks.postToolUse, <String>['/usr/bin/true']);
    expect(config.hooks.stop, <String>['echo stop']);
  });
}

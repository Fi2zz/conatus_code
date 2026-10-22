/// `[providers.*]` 的 session_header / user_agent 解析。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-provider-cfg');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final File file = File('${dir.path}${Platform.pathSeparator}$kConfigFileName');
  file.writeAsStringSync(content);
  return file.path;
}

ConatusCodeConfig _load(String toml) => loadConfig(path: _writeToml(toml));

void main() {
  test('session_header / user_agent 缺省为空', () {
    final ConatusCodeConfig config = _load('''
[providers.opencode-go]
base_url = "https://opencode.ai/inference/go/openai/v1"
''');

    expect(config.providers.single.sessionHeader, '');
    expect(config.providers.single.userAgent, '');
  });

  test('session_header / user_agent 被读取', () {
    final ConatusCodeConfig config = _load('''
[providers.opencode-go]
base_url = "https://opencode.ai/inference/go/openai/v1"
session_header = "x-opencode-sessionid"
user_agent = "nava/0.1.0"
''');

    expect(config.providers.single.sessionHeader, 'x-opencode-sessionid');
    expect(config.providers.single.userAgent, 'nava/0.1.0');
  });
}

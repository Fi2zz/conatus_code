import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

String _toml(String body) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-safety-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}${Platform.pathSeparator}$kConfigFileName')
    ..writeAsStringSync(body);
  return file.path;
}

void main() {
  test('缺省值', () {
    final ConatusCodeConfig c = loadConfig(path: _toml('[agent]\n'));
    expect(c.safety.requireReadBeforeWrite, isTrue);
    expect(c.safety.repeatWarnAt, 3);
    expect(c.safety.repeatDenyAt, 5);
    expect(c.safety.protectPrivateKeys, isTrue);
    expect(c.safety.denyDotenvWrites, isTrue);
    expect(c.safety.repeatExemptTools, isEmpty);
  });

  test('完整解析', () {
    final ConatusCodeConfig c = loadConfig(
      path: _toml('''
[safety]
require_read_before_write = false
repeat_warn_at = 2
repeat_deny_at = 4
repeat_exempt_tools = ["bash"]
protect_private_keys = false
deny_dotenv_writes = false
extra_sensitive_paths = ["secrets"]
'''),
    );
    expect(c.safety.requireReadBeforeWrite, isFalse);
    expect(c.safety.repeatWarnAt, 2);
    expect(c.safety.repeatDenyAt, 4);
    expect(c.safety.repeatExemptTools, <String>['bash']);
    expect(c.safety.extraSensitivePaths, <String>['secrets']);
  });

  test('deny <= warn 报错；负数报错', () {
    expect(
      () => loadConfig(
        path: _toml('[safety]\nrepeat_warn_at = 5\nrepeat_deny_at = 3\n'),
      ),
      throwsA(isA<ConfigException>()),
    );
    expect(
      () => loadConfig(path: _toml('[safety]\nrepeat_deny_at = -1\n')),
      throwsA(isA<ConfigException>()),
    );
  });
}

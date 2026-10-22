/// `[[permissions]]` 配置解析：顺序、字段校验与非法值拒绝。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

/// 把 [toml] 写进临时 config.toml 并解析。
ConatusCodeConfig _load(String toml) {
  final Directory dir = Directory.systemTemp.createTempSync('perm-config');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}${Platform.pathSeparator}$kConfigFileName')
    ..writeAsStringSync(toml);
  return loadConfig(path: file.path);
}

/// 断言 [body] 抛 [ConfigException] 且消息含 [fragment]。
void _expectConfigError(String fragment, void Function() body) {
  expect(
    body,
    throwsA(
      isA<ConfigException>().having(
        (ConfigException error) => error.message,
        'message',
        contains(fragment),
      ),
    ),
  );
}

void main() {
  test('[[permissions]] 按书写顺序解析为规则列表', () {
    final ConatusCodeConfig config = _load('''
[[permissions]]
action = "shell"
resource = "git push *"
effect = "deny"

[[permissions]]
action = "read_file"
resource = "/tmp/*"
effect = "allow"
''');

    expect(config.permissions.rules, hasLength(2));
    final PermissionRule first = config.permissions.rules.first;
    expect(first.action, 'shell');
    expect(first.resource, 'git push *');
    expect(first.effect, PermissionEffect.deny);
    expect(first.source, 'config');
    expect(config.permissions.rules.last.effect, PermissionEffect.allow);
  });

  test('缺省没有任何规则', () {
    expect(_load('').permissions.rules, isEmpty);
  });

  test('effect 取值非法时抛 ConfigException', () {
    _expectConfigError('effect', () {
      _load('''
[[permissions]]
action = "shell"
resource = "*"
effect = "block"
''');
    });
  });

  test('缺 action / resource / effect 都抛 ConfigException', () {
    _expectConfigError('action', () {
      _load('[[permissions]]\nresource = "*"\neffect = "allow"\n');
    });
    _expectConfigError('resource', () {
      _load('[[permissions]]\naction = "shell"\neffect = "allow"\n');
    });
    _expectConfigError('effect', () {
      _load('[[permissions]]\naction = "shell"\nresource = "*"\n');
    });
  });

  test('字段类型不符时抛 ConfigException', () {
    _expectConfigError('action', () {
      _load('''
[[permissions]]
action = 1
resource = "*"
effect = "allow"
''');
    });
    _expectConfigError('permissions', () {
      _load('permissions = "nope"\n');
    });
  });
}

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
action = "bash"
resource = "git push *"
effect = "deny"

[[permissions]]
action = "read"
resource = "/tmp/*"
effect = "allow"
''');

    expect(config.permissions.rules, hasLength(2));
    final PermissionRule first = config.permissions.rules.first;
    expect(first.action, 'bash');
    expect(first.resource, 'git push *');
    expect(first.effect, PermissionEffect.deny);
    expect(first.source, 'config');
    expect(config.permissions.rules.last.effect, PermissionEffect.allow);
  });

  test('路径动作的规则资源会规范化（./ 折叠）', () {
    final ConatusCodeConfig config = _load('''
[[permissions]]
action = "edit"
resource = "./src/../src/*.env"
effect = "deny"
''');
    expect(config.permissions.rules.single.resource, 'src/*.env');
  });

  test('工具名归一为规范 action（write/apply_patch/list/run_tests）', () {
    final ConatusCodeConfig config = _load('''
[[permissions]]
action = "write"
resource = "src/*"
effect = "allow"

[[permissions]]
action = "apply_patch"
resource = "*"
effect = "deny"

[[permissions]]
action = "list"
resource = "/tmp/*"
effect = "deny"

[[permissions]]
action = "run_tests"
resource = "dart test"
effect = "ask"
''');

    expect(
      config.permissions.rules.map((PermissionRule r) => r.action),
      <String>['edit', 'edit', 'read', 'bash'],
    );
  });

  test('缺省没有任何规则', () {
    expect(_load('').permissions.rules, isEmpty);
  });

  test('effect 取值非法时抛 ConfigException', () {
    _expectConfigError('effect', () {
      _load('''
[[permissions]]
action = "bash"
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
      _load('[[permissions]]\naction = "bash"\neffect = "allow"\n');
    });
    _expectConfigError('effect', () {
      _load('[[permissions]]\naction = "bash"\nresource = "*"\n');
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

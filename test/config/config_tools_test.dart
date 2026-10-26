/// `[[tools]]` 配置解析：CLI / HTTP 后端与参数 schema。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart' show ToolRisk;
import 'package:test/test.dart';

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-tools-cfg-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File(
    '${dir.path}${Platform.pathSeparator}$kConfigFileName',
  );
  file.writeAsStringSync(content);
  return file.path;
}

ConatusCodeConfig _load(String toml) => loadConfig(path: _writeToml(toml));

void _expectError(String fragment, String toml) {
  expect(
    () => _load(toml),
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
  test('CLI 工具：参数、env、cwd、risk 与 timeout', () {
    final ConatusCodeConfig config = _load('''
[[tools]]
name = "deploy"
description = "Deploy a service"
command = "node"
args = ["tools/deploy.mjs"]
cwd = "tools"
timeout_ms = 5000
risk = "medium"
env = { TOKEN = "\${TOKEN}" }

[[tools.params]]
name = "environment"
type = "string"
required = true
description = "target environment"

[[tools.params]]
name = "level"
type = "enum"
values = ["low", "high"]
default = "low"
''');

    final CustomToolConfig tool = config.tools.single;
    expect(tool.isCommand, isTrue);
    expect(tool.command, 'node');
    expect(tool.args, <String>['tools/deploy.mjs']);
    expect(tool.cwd, 'tools');
    expect(tool.timeoutMs, 5000);
    expect(tool.risk, ToolRisk.medium);
    expect(tool.env['TOKEN'], r'${TOKEN}');
    expect(tool.params, hasLength(2));
    expect(tool.params.first.required, isTrue);
    expect(tool.params.last.enumValues, <String>['low', 'high']);
    expect(tool.params.last.defaultValue, 'low');
  });

  test('HTTP 工具：url / method / headers', () {
    final ConatusCodeConfig config = _load('''
[[tools]]
name = "lookup"
description = "Look up a record"
url = "https://tools.example.com/lookup"
method = "put"
headers = { Authorization = "Bearer \${TOKEN}" }
''');

    final CustomToolConfig tool = config.tools.single;
    expect(tool.isCommand, isFalse);
    expect(tool.url, 'https://tools.example.com/lookup');
    expect(tool.method, 'PUT');
    expect(tool.headers['Authorization'], r'Bearer ${TOKEN}');
  });

  test('必须且只能声明 command 或 url 之一', () {
    _expectError('必须且只能声明', '''
[[tools]]
name = "none"
description = "x"
''');
    _expectError('必须且只能声明', '''
[[tools]]
name = "both"
description = "x"
command = "a"
url = "https://example.com"
''');
  });

  test('名称 / 描述 / 重复 / risk / 参数类型校验', () {
    _expectError('name 不能为空', '''
[[tools]]
description = "x"
command = "a"
''');
    _expectError('description 不能为空', '''
[[tools]]
name = "x"
command = "a"
''');
    _expectError('重复声明', '''
[[tools]]
name = "x"
description = "a"
command = "a"

[[tools]]
name = "x"
description = "b"
command = "b"
''');
    _expectError('risk', '''
[[tools]]
name = "x"
description = "a"
command = "a"
risk = "critical"
''');
    _expectError('不支持', '''
[[tools]]
name = "x"
description = "a"
command = "a"

[[tools.params]]
name = "p"
type = "object"
''');
    _expectError('default 类型', '''
[[tools]]
name = "x"
description = "a"
command = "a"

[[tools.params]]
name = "p"
type = "integer"
default = "not-int"
''');
    _expectError('http(s)', '''
[[tools]]
name = "x"
description = "a"
url = "ftp://example.com"
''');
    _expectError('method', '''
[[tools]]
name = "x"
description = "a"
url = "https://example.com"
method = "TRACE"
''');
  });
}

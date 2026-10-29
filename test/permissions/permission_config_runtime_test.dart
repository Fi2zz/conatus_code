/// Important 9：config → runtime 的权限装配与「权限最外层」顺序。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

const String _denyToml = '''
[[permissions]]
action = "edit"
resource = "src/*"
effect = "deny"
''';

ConatusCodeConfig _config(String toml, Directory dir) {
  final File file = File('${dir.path}${Platform.pathSeparator}config.toml')
    ..writeAsStringSync(toml);
  return loadConfig(path: file.path);
}

Future<ConatusTuiRuntime> _runtime(
  Directory work, {
  required PermissionConfig permissions,
  HooksConfig? hooks,
}) async {
  final Directory base = Directory.systemTemp.createTempSync('nava-perm-base');
  addTearDown(() => base.deleteSync(recursive: true));
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    baseDir: base.path,
    sessionDir: '${base.path}${Platform.pathSeparator}sessions',
    memoryFile: '${base.path}${Platform.pathSeparator}memory.json',
    workdir: work.path,
    webTools: false,
    skills: false,
    interactive: false,
    permissions: permissions,
    hooks: hooks,
  );
  addTearDown(runtime.dispose);
  return runtime;
}

void main() {
  test('TOML [[permissions]] 经 runtime 装配后拦住绝对路径调用', () async {
    final Directory work = Directory.systemTemp.createTempSync('nava-perm-rt');
    final Directory configDir = Directory.systemTemp.createTempSync(
      'nava-perm-cfg',
    );
    addTearDown(() {
      work.deleteSync(recursive: true);
      configDir.deleteSync(recursive: true);
    });
    final ConatusCodeConfig config = _config(_denyToml, configDir);
    final ConatusTuiRuntime runtime = await _runtime(
      work,
      permissions: config.permissions,
    );
    final String target =
        '${work.path}${Platform.pathSeparator}src${Platform.pathSeparator}x.dart';

    final ToolResult result = await runtime.tools.call(
      ToolCall(
        name: 'write',
        arguments: <String, Object?>{'path': target, 'content': 'x'},
      ),
    );

    expect(result.error?.code, 'PERMISSION_DENIED');
    expect(File(target).existsSync(), isFalse);
  });

  test('权限最外层：被 deny 的调用不会触发 pre_tool_use hook', () async {
    final Directory work = Directory.systemTemp.createTempSync('nava-perm-rt');
    final Directory configDir = Directory.systemTemp.createTempSync(
      'nava-perm-cfg',
    );
    addTearDown(() {
      work.deleteSync(recursive: true);
      configDir.deleteSync(recursive: true);
    });
    final File marker = File('${work.path}${Platform.pathSeparator}hook.log');
    final ConatusCodeConfig config = _config(_denyToml, configDir);
    final ConatusTuiRuntime runtime = await _runtime(
      work,
      permissions: config.permissions,
      hooks: HooksConfig(preToolUse: <String>['touch ${marker.path}']),
    );

    final ToolResult denied = await runtime.tools.call(
      const ToolCall(
        name: 'write',
        arguments: <String, Object?>{'path': 'src/x.dart', 'content': 'x'},
      ),
    );
    expect(denied.error?.code, 'PERMISSION_DENIED');
    expect(marker.existsSync(), isFalse, reason: 'deny 的调用不该走到 hook');

    final ToolResult allowed = await runtime.tools.call(
      const ToolCall(
        name: 'write',
        arguments: <String, Object?>{'path': 'ok.txt', 'content': 'ok'},
      ),
    );
    expect(allowed.isError, isFalse);
    expect(marker.existsSync(), isTrue, reason: '放行的调用照常跑 hook');
  });
}

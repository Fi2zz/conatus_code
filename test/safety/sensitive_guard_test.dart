import 'dart:io';

import 'package:conatus_code/safety.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _PathTool extends Tool {
  const _PathTool(this.name);

  @override
  final String name;

  @override
  String get description => '路径参数测试工具';

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success('ok');
}

class _BashTool extends Tool {
  const _BashTool();

  @override
  String get name => 'bash';

  @override
  String get description => '命令测试工具';

  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success('ok');
}

class _PatchTool extends Tool {
  const _PatchTool();

  @override
  String get name => 'apply_patch';

  @override
  String get description => '补丁测试工具';

  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success('ok');
}

void main() {
  late Directory home;
  late ToolRegistry tools;
  late SensitivePathGuard guard;

  setUp(() {
    home = Directory.systemTemp.createTempSync('nava-sensitive');
    tools = ToolRegistry()
      ..register(const _PathTool('read'))
      ..register(const _PathTool('write'))
      ..register(const _BashTool())
      ..register(const _PatchTool());
    guard = SensitivePathGuard(
      tools: tools,
      workdir: home.path,
      home: home.path,
    );
  });
  tearDown(() => home.deleteSync(recursive: true));

  ToolCall call(String tool, String path) =>
      ToolCall(name: tool, arguments: <String, Object?>{'path': path});

  test('私钥读写拒绝；.env 读放行、写拒绝', () {
    expect(
      guard.check(call('read', '~/.ssh/id_rsa')),
      startsWith('SENSITIVE_PATH:'),
    );
    expect(
      guard.check(call('write', '~/.ssh/id_rsa')),
      startsWith('SENSITIVE_PATH:'),
    );
    expect(guard.check(call('read', '.env')), isNull);
    expect(guard.check(call('write', '.env')), startsWith('SENSITIVE_PATH:'));
  });

  test('denyDotenvWrites=false 时 .env 写放行', () {
    final SensitivePathGuard relaxed = SensitivePathGuard(
      tools: tools,
      workdir: home.path,
      home: home.path,
      denyDotenvWrites: false,
    );
    expect(relaxed.check(call('write', '.env')), isNull);
  });

  test('bash 字面私钥路径拒绝；普通命令放行', () {
    expect(
      guard.check(
        const ToolCall(
          name: 'bash',
          arguments: <String, Object?>{'command': 'cat ~/.ssh/id_rsa'},
        ),
      ),
      startsWith('SENSITIVE_PATH:'),
    );
    expect(
      guard.check(
        const ToolCall(
          name: 'bash',
          arguments: <String, Object?>{'command': 'echo hi > out.txt'},
        ),
      ),
      isNull,
    );
  });

  test('apply_patch 命中凭据路径拒绝', () {
    expect(
      guard.check(
        const ToolCall(
          name: 'apply_patch',
          arguments: <String, Object?>{
            'patch':
                '*** Begin Patch\n*** Update File: credentials\n+x\n'
                '*** End Patch',
          },
        ),
      ),
      startsWith('SENSITIVE_PATH:'),
    );
  });

  test('protectPrivateKeys=false 关闭私钥阻断', () {
    final SensitivePathGuard relaxed = SensitivePathGuard(
      tools: tools,
      workdir: home.path,
      home: home.path,
      protectPrivateKeys: false,
    );
    expect(relaxed.check(call('read', '~/.ssh/id_rsa')), isNull);
  });
}

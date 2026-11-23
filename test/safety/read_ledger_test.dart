import 'dart:io';

import 'package:conatus_code/safety.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _ReadTool extends Tool {
  const _ReadTool({this.withVersion = true});

  final bool withVersion;

  @override
  String get name => 'read';

  @override
  String get description => '读取文件';

  @override
  List<ParamSpec> get params => <ParamSpec>[
    ParamSpec.string('path', required: true),
  ];

  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success(
    'body',
    value: <String, Object?>{
      'path': ctx.str('path'),
      if (withVersion) 'version': 'v1',
    },
  );
}

class _FailingReadTool extends Tool {
  const _FailingReadTool();

  @override
  String get name => 'read';

  @override
  String get description => '读取文件';

  @override
  List<ParamSpec> get params => <ParamSpec>[
    ParamSpec.string('path', required: true),
  ];

  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.failure(
    'boom',
    error: const ToolError('FS_NOT_FOUND', 'boom'),
  );
}

void main() {
  late Directory dir;
  late ReadLedger ledger;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-ledger');
    ledger = ReadLedger();
    File('${dir.path}${Platform.pathSeparator}a.txt').writeAsStringSync('x');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('read 成功后登记 canonical 路径指纹', () async {
    final ToolRegistry tools = ToolRegistry()..register(const _ReadTool());
    tools.use(ReadLedgerMiddleware(ledger: ledger, workdir: dir.path).call);
    await tools.call(
      const ToolCall(
        name: 'read',
        arguments: <String, Object?>{'path': 'a.txt'},
      ),
    );
    final String key = canonicalToolPath(dir.path, null, 'a.txt')!;
    expect(ledger.length, 1);
    expect(ledger.fingerprintOf(key), isNotNull);
  });

  test('无 version 的读取不登记', () async {
    final ToolRegistry tools = ToolRegistry()
      ..register(const _ReadTool(withVersion: false));
    tools.use(ReadLedgerMiddleware(ledger: ledger, workdir: dir.path).call);
    await tools.call(
      const ToolCall(
        name: 'read',
        arguments: <String, Object?>{'path': 'a.txt'},
      ),
    );
    expect(ledger.length, 0);
  });

  test('失败的读取不登记', () async {
    final ToolRegistry tools = ToolRegistry()
      ..register(const _FailingReadTool());
    tools.use(ReadLedgerMiddleware(ledger: ledger, workdir: dir.path).call);
    await tools.call(
      const ToolCall(
        name: 'read',
        arguments: <String, Object?>{'path': 'a.txt'},
      ),
    );
    expect(ledger.length, 0);
  });

  test('fileFingerprint 随文件内容变化', () {
    final String key = canonicalToolPath(dir.path, null, 'a.txt')!;
    final String? before = fileFingerprint(key);
    File(key).writeAsStringSync('changed content');
    expect(fileFingerprint(key), isNot(before));
    expect(
      fileFingerprint('${dir.path}${Platform.pathSeparator}missing.txt'),
      isNull,
    );
  });
}

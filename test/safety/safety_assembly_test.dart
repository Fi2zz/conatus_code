import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/fs_tools.dart';
import 'package:conatus_code/safety.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('nava-safety-asm'));
  tearDown(() => dir.deleteSync(recursive: true));

  Context build(SafetyConfig config) {
    final Context app = Context.root();
    provideTools(app);
    provideFsTools(
      app,
      options: FsToolOptions(
        fs: LocalFileSystem(cwd: dir.path),
        enableSearch: false,
      ),
    );
    provideToolSafety(app, workdir: dir.path, config: config);
    addTearDown(app.dispose);
    return app;
  }

  test('默认开启：未读覆盖被拒，读后可写', () async {
    File('${dir.path}${Platform.pathSeparator}a.txt').writeAsStringSync('old');
    final Context app = build(const SafetyConfig());
    final ToolResult denied = await app.tools.call(
      const ToolCall(
        name: 'write',
        arguments: <String, Object?>{
          'path': 'a.txt',
          'content': 'new',
          'mode': 'overwrite',
        },
      ),
    );
    expect(denied.isError, isTrue);
    expect(denied.content, startsWith('WRITE_WITHOUT_READ:'));
    await app.tools.call(
      const ToolCall(
        name: 'read',
        arguments: <String, Object?>{'path': 'a.txt'},
      ),
    );
    final ToolResult allowed = await app.tools.call(
      const ToolCall(
        name: 'write',
        arguments: <String, Object?>{
          'path': 'a.txt',
          'content': 'new',
          'mode': 'overwrite',
        },
      ),
    );
    expect(allowed.isError, isFalse);
  });

  test('全关：未读覆盖放行', () async {
    File('${dir.path}${Platform.pathSeparator}a.txt').writeAsStringSync('old');
    final Context app = build(
      const SafetyConfig(
        requireReadBeforeWrite: false,
        repeatWarnAt: 0,
        repeatDenyAt: 0,
        protectPrivateKeys: false,
        denyDotenvWrites: false,
      ),
    );
    final ToolResult r = await app.tools.call(
      const ToolCall(
        name: 'write',
        arguments: <String, Object?>{
          'path': 'a.txt',
          'content': 'new',
          'mode': 'overwrite',
        },
      ),
    );
    expect(r.isError, isFalse);
  });

  test('resetSession 清空台账与计数', () {
    final Context app = build(const SafetyConfig());
    final ToolSafety safety = app.require<ToolSafety>('toolSafety');
    safety.ledger.note('/x', 'v');
    expect(safety.ledger.length, 1);
    safety.resetSession();
    expect(safety.ledger.length, 0);
  });
}

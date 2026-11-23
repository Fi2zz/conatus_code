import 'dart:io';

import 'package:conatus_code/safety.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late ReadLedger ledger;
  late ReadBeforeWriteGuard guard;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-write-guard');
    file = File('${dir.path}${Platform.pathSeparator}a.txt')
      ..writeAsStringSync('old');
    ledger = ReadLedger();
    guard = ReadBeforeWriteGuard(ledger: ledger, workdir: dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ToolCall write(String path) =>
      ToolCall(name: 'write', arguments: <String, Object?>{'path': path});

  test('未读覆盖已有文件被拒', () {
    expect(guard.check(write('a.txt')), startsWith('WRITE_WITHOUT_READ:'));
  });

  test('读过且未变化放行；变化后拒绝', () {
    final String key = canonicalToolPath(dir.path, null, 'a.txt')!;
    ledger.note(key, fileFingerprint(key)!);
    expect(guard.check(write('a.txt')), isNull);
    File(key).writeAsStringSync('changed');
    expect(guard.check(write('./a.txt')), startsWith('WRITE_STALE_READ:'));
  });

  test('新建文件放行；其他工具放行', () {
    expect(guard.check(write('new.txt')), isNull);
    expect(
      guard.check(
        const ToolCall(
          name: 'read',
          arguments: <String, Object?>{'path': 'a.txt'},
        ),
      ),
      isNull,
    );
  });

  test('apply_patch：Add 放行，Update 未读拒绝', () {
    expect(
      guard.check(
        const ToolCall(
          name: 'apply_patch',
          arguments: <String, Object?>{
            'patch':
                '*** Begin Patch\n*** Add File: new.txt\n+x\n*** End Patch',
          },
        ),
      ),
      isNull,
    );
    expect(
      guard.check(
        const ToolCall(
          name: 'apply_patch',
          arguments: <String, Object?>{'patch': '--- a/a.txt\n+++ b/a.txt\n'},
        ),
      ),
      startsWith('WRITE_WITHOUT_READ:'),
    );
  });

  test('符号链接别名命中同一台账', () {
    if (Platform.isWindows) return;
    Link('${dir.path}${Platform.pathSeparator}alias.txt').createSync(file.path);
    final String key = canonicalToolPath(dir.path, null, 'a.txt')!;
    ledger.note(key, fileFingerprint(key)!);
    expect(guard.check(write('alias.txt')), isNull);
  });

  test('补丁声称新建但文件已存在时仍要求先读', () {
    expect(
      guard.check(
        const ToolCall(
          name: 'apply_patch',
          arguments: <String, Object?>{
            'patch': '--- /dev/null\n+++ b/a.txt\n@@ -0,0 +1 @@\n+x\n',
          },
        ),
      ),
      startsWith('WRITE_WITHOUT_READ:'),
    );
  });

  test('含 .. 的未归一化路径命中同一文件', () {
    expect(
      guard.check(write('nope/../a.txt')),
      startsWith('WRITE_WITHOUT_READ:'),
    );
  });

  test('OpenCode Delete 要求先读', () {
    expect(
      guard.check(
        const ToolCall(
          name: 'apply_patch',
          arguments: <String, Object?>{
            'patch': '*** Begin Patch\n*** Delete File: a.txt\n*** End Patch',
          },
        ),
      ),
      startsWith('WRITE_WITHOUT_READ:'),
    );
  });

  test('~ 按 fs 字面语义解析，与真实写入路径一致', () {
    Directory('${dir.path}${Platform.pathSeparator}~').createSync();
    File(
      '${dir.path}${Platform.pathSeparator}~${Platform.pathSeparator}n.txt',
    ).writeAsStringSync('x');
    expect(guard.check(write('~/n.txt')), startsWith('WRITE_WITHOUT_READ:'));
  });
}

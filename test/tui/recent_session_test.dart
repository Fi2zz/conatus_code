/// `--continue` 与最近会话恢复：文件 mtime 取最新、规范 id 过滤。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

String _dir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-recent');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir.path;
}

void main() {
  test('取修改时间最新的规范会话；非规范文件跳过', () {
    final String dir = _dir();
    const String a = 'session_11111111-2222-3333-4444-555555555555';
    const String b = 'session_aaaaaaaa-2222-3333-4444-555555555555';
    File('$dir${Platform.pathSeparator}tui.jsonl').writeAsStringSync('x');
    File('$dir${Platform.pathSeparator}$a.jsonl').writeAsStringSync('x');
    File('$dir${Platform.pathSeparator}$b.jsonl').writeAsStringSync('x');
    // 让 b 的 mtime 更新。
    final File fileB = File('$dir${Platform.pathSeparator}$b.jsonl');
    fileB.writeAsStringSync('x', flush: true);
    final DateTime now = DateTime.now();
    fileB.setLastModifiedSync(now.add(const Duration(seconds: 10)));

    expect(findRecentSessionId(dir), b);
  });

  test('目录不存在 → null', () {
    final String missing = '${Directory.systemTemp.path}/nope-${DateTime.now().microsecondsSinceEpoch}';
    expect(findRecentSessionId(missing), isNull);
  });

  test('只有非规范文件 → null', () {
    final String dir = _dir();
    File('$dir${Platform.pathSeparator}tui.jsonl').writeAsStringSync('x');
    expect(findRecentSessionId(dir), isNull);
  });

  test('空目录 → null', () {
    expect(findRecentSessionId(_dir()), isNull);
  });

  test('非 .jsonl 文件不影响结果', () {
    final String dir = _dir();
    File('$dir${Platform.pathSeparator}readme.md').writeAsStringSync('x');
    expect(findRecentSessionId(dir), isNull);
  });

  test('--continue 解析与 --session 优先语义', () {
    expect(
      TuiOptions.parse(const <String>['--continue']).continueRequested,
      isTrue,
    );
    expect(TuiOptions.parse(const <String>[]).continueRequested, isFalse);
    // --session 存在时 --continue 也在，bin 侧按 session 优先。
    expect(
      TuiOptions.parse(const <String>[
        '--continue',
        '--session',
        'session_c8898262-4a76-4bd4-93dc-f757fd4ef666',
      ]).session,
      'session_c8898262-4a76-4bd4-93dc-f757fd4ef666',
    );
  });

  test('usage 文案含 --continue', () {
    expect(TuiOptions.usage, contains('--continue'));
  });
}

/// 退出恢复提示：同步写 tty，失败回退 sink。
library;

import 'dart:io';

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

void main() {
  test('writeResumeHint 同步写 tty 文件', () {
    final Directory dir = Directory.systemTemp.createTempSync('nava-hint-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String path = '${dir.path}/tty';
    File(path).writeAsStringSync('');

    writeResumeHint(
      'session_11111111-1111-4111-8111-111111111111',
      ttyPath: path,
      fallback: StringBuffer(),
    );

    final String text = File(path).readAsStringSync();
    expect(text, contains('恢复本次会话：'));
    expect(
      text,
      contains('nava -r session_11111111-1111-4111-8111-111111111111'),
    );
  });

  test('tty 不存在时回退 fallback', () {
    final StringBuffer fallback = StringBuffer();
    writeResumeHint(
      'session_abc',
      ttyPath: '/definitely/not/a/tty',
      fallback: fallback,
    );
    expect(fallback.toString(), contains('nava -r session_abc'));
  });
}

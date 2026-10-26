/// 定义目录监听：变更合并、停止后不再触发。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  test('目录内新增文件触发一次失效', () async {
    final Directory root = Directory.systemTemp.createTempSync('nava-def-watch-');
    addTearDown(() => root.deleteSync(recursive: true));
    final Completer<void> signal = Completer<void>();
    int calls = 0;
    final DefinitionWatcher watcher = DefinitionWatcher(
      roots: <String>[root.path],
      debounce: const Duration(milliseconds: 30),
      onInvalidate: () {
        calls++;
        if (!signal.isCompleted) signal.complete();
      },
    );
    final void Function() stop = watcher.start();
    addTearDown(stop);

    File('${root.path}/a.md').writeAsStringSync('x');
    await signal.future.timeout(const Duration(seconds: 2));

    expect(calls, 1);
    stop();
    File('${root.path}/b.md').writeAsStringSync('y');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(calls, 1);
  });
}

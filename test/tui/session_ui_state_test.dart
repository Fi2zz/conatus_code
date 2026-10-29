/// 会话 UI sidecar：滚动位置与输入历史的读写、上限与损坏降级。
library;

import 'dart:io';

import 'package:conatus_code/src/tui/session_ui_state.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-ui-state');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void main() {
  test('缺失文件返回空状态', () async {
    final SessionUiStateStore store = SessionUiStateStore(dir: _tempDir().path);

    final SessionUiState state = await store.load('session_x');

    expect(state.scrollOffset, isNull);
    expect(state.history, isEmpty);
  });

  test('保存后读回滚动位置与输入历史', () async {
    final Directory dir = _tempDir();
    final SessionUiStateStore store = SessionUiStateStore(dir: dir.path);
    const SessionUiState state = SessionUiState(
      scrollOffset: 42.5,
      history: <String>['第一句', '/sessions'],
    );

    await store.save('session_x', state);
    final SessionUiState loaded = await store.load('session_x');

    expect(loaded.scrollOffset, 42.5);
    expect(loaded.history, <String>['第一句', '/sessions']);
    expect(File('${dir.path}/session_x.json').existsSync(), isTrue);
  });

  test('连续重复输入折叠，历史最多 100 条', () {
    SessionUiState state = SessionUiState.empty;
    state = state.withInput('a');
    state = state.withInput('a');
    expect(state.history, <String>['a']);

    for (int i = 0; i < kSessionUiHistoryLimit + 5; i++) {
      state = state.withInput('v$i');
    }
    expect(state.history, hasLength(kSessionUiHistoryLimit));
    expect(state.history.last, 'v${kSessionUiHistoryLimit + 4}');
  });

  test('损坏 JSON 返回空状态而不是抛错', () async {
    final Directory dir = _tempDir();
    final SessionUiStateStore store = SessionUiStateStore(dir: dir.path);
    File('${dir.path}/session_bad.json').writeAsStringSync('{not json');

    final SessionUiState state = await store.load('session_bad');

    expect(state.history, isEmpty);
    expect(state.scrollOffset, isNull);
  });
}

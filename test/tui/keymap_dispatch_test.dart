/// 全局 dispatcher：两段式 leader、超时与默认键位动作。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

KeyboardEvent _key(LogicalKey key, {bool ctrl = false}) => KeyboardEvent(
  logicalKey: key,
  modifiers: ModifierKeys(ctrl: ctrl),
);

Keymap _leaderKeymap() => Keymap.fromConfig(<String, String>{
  'leader': 'ctrl+x',
  'model.list': '<leader>m',
});

void main() {
  test('leader 两段式：先按 leader 再按后续键', () {
    final KeymapDispatcher dispatcher = KeymapDispatcher(_leaderKeymap());
    addTearDown(dispatcher.dispose);

    expect(dispatcher.dispatch(_key(LogicalKey.keyX, ctrl: true)), isNull);
    expect(dispatcher.leaderPending, isTrue);
    expect(dispatcher.dispatch(_key(LogicalKey.keyM)), KeyActions.modelList);
    expect(dispatcher.leaderPending, isFalse);
  });

  test('leader 超时后复位，后续键不再触发动作', () async {
    final KeymapDispatcher dispatcher = KeymapDispatcher(
      _leaderKeymap(),
      leaderTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(dispatcher.dispose);

    expect(dispatcher.dispatch(_key(LogicalKey.keyX, ctrl: true)), isNull);
    expect(dispatcher.leaderPending, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(dispatcher.leaderPending, isFalse);
    expect(dispatcher.dispatch(_key(LogicalKey.keyM)), isNull);
  });

  test('leader 后按未映射键：复位且不落到普通表', () {
    final KeymapDispatcher dispatcher = KeymapDispatcher(_leaderKeymap());
    addTearDown(dispatcher.dispose);

    dispatcher.dispatch(_key(LogicalKey.keyX, ctrl: true));
    // ctrl+l 是普通表的 app.clear，但作为 leader 第二段不应触发。
    expect(dispatcher.dispatch(_key(LogicalKey.keyL, ctrl: true)), isNull);
    expect(dispatcher.leaderPending, isFalse);
  });

  test('默认 keymap 经 dispatcher 仍返回退出动作', () {
    final KeymapDispatcher dispatcher = KeymapDispatcher(
      Keymap.fromConfig(const <String, String>{}),
    );
    addTearDown(dispatcher.dispose);
    expect(
      dispatcher.dispatch(_key(LogicalKey.keyC, ctrl: true)),
      KeyActions.exit,
    );
    expect(
      dispatcher.dispatch(_key(LogicalKey.keyL, ctrl: true)),
      KeyActions.clear,
    );
  });
}

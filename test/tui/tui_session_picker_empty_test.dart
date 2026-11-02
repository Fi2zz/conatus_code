/// 会话面板：空壳会话不进入列表（当前会话除外）。
library;

import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  test('无用户消息且非当前会话的空壳被隐藏', () async {
    final SessionStore store = SessionStore();

    final Session empty = store.create();
    empty
      ..append('plan/mode', data: <String, Object?>{'state': 'active'})
      ..append('agent/selected', data: <String, Object?>{'id': 'build'});

    final Session used = store.create();
    used.append(kUserMessageEvent, data: <String, Object?>{'text': '你好'});

    final TuiSessionPicker picker = TuiSessionPicker(store, onChanged: () {});
    await picker.show(used.id);
    expect(picker.list.map((TuiSessionInfo info) => info.id), <String>[
      used.id,
    ]);

    // 当前会话即使还是空壳也保留，避免 `*` 标记消失。
    await picker.show(empty.id);
    expect(picker.list.map((TuiSessionInfo info) => info.id).toSet(), <String>{
      empty.id,
      used.id,
    });
  });
}

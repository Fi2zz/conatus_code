/// 键位解析与 Keymap：默认值、leader 展开、关闭与冲突消解。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

KeyboardEvent _key(LogicalKey key, {bool ctrl = false, bool shift = false}) =>
    KeyboardEvent(
      logicalKey: key,
      modifiers: ModifierKeys(ctrl: ctrl, shift: shift),
    );

void main() {
  group('parseKeyBinding', () {
    test('解析 ctrl / alt / shift / meta 与功能键', () {
      final KeyBinding ctrlX = parseKeyBinding('ctrl+x')!;
      expect(ctrlX.key, LogicalKey.keyX);
      expect(ctrlX.ctrl, isTrue);
      expect(ctrlX.label, 'ctrl+x');

      final KeyBinding altEnter = parseKeyBinding('alt+enter')!;
      expect(altEnter.key, LogicalKey.enter);
      expect(altEnter.alt, isTrue);

      final KeyBinding shiftTab = parseKeyBinding('shift+tab')!;
      expect(shiftTab.key, LogicalKey.tab);
      expect(shiftTab.shift, isTrue);

      expect(parseKeyBinding('f1')!.key, LogicalKey.f1);
      expect(parseKeyBinding('Ctrl+Shift+Tab')!.label, 'ctrl+shift+tab');
    });

    test('leader 前缀只取后续键（两段式由 dispatcher 负责）', () {
      final KeyBinding? binding = parseKeyBinding(
        '<leader>m',
        leader: LogicalKey.keyX,
      );
      expect(binding?.key, LogicalKey.keyM);
      expect(parseKeyBinding('<leader>'), isNull);
    });

    test('none / false / 未知键名返回 null', () {
      expect(parseKeyBinding('none'), isNull);
      expect(parseKeyBinding('false'), isNull);
      expect(parseKeyBinding('ctrl+not-a-key'), isNull);
      expect(parseKeyBinding('hyper+x'), isNull);
    });
  });

  group('Keymap 默认值与冲突', () {
    test('默认 keymap 保留退出键与清屏键', () {
      final Keymap keymap = Keymap.fromConfig(const <String, String>{});
      expect(
        keymap.actionFor(_key(LogicalKey.keyC, ctrl: true)),
        KeyActions.exit,
      );
      expect(
        keymap.actionFor(_key(LogicalKey.keyD, ctrl: true)),
        KeyActions.exit,
      );
      expect(
        keymap.actionFor(_key(LogicalKey.keyL, ctrl: true)),
        KeyActions.clear,
      );
      expect(keymap.actionFor(_key(LogicalKey.f1)), KeyActions.help);
      expect(keymap.leader?.key, LogicalKey.keyX);
      expect(keymap.warnings, isEmpty);
    });

    test('<leader> 动作不参与单键 actionFor，需查 leader 表', () {
      final Keymap keymap = Keymap.fromConfig(<String, String>{
        'leader': 'ctrl+x',
        'model.list': '<leader>m',
      });
      expect(keymap.actionFor(_key(LogicalKey.keyM)), isNull);
      expect(
        keymap.actionForLeaderKey(_key(LogicalKey.keyM)),
        KeyActions.modelList,
      );
    });

    test('none / false 关闭动作', () {
      final Keymap keymap = Keymap.fromConfig(<String, String>{
        'app.exit': 'none',
        'help.show': 'false',
      });
      expect(keymap.actionFor(_key(LogicalKey.keyC, ctrl: true)), isNull);
      expect(keymap.actionFor(_key(LogicalKey.keyD, ctrl: true)), isNull);
      expect(keymap.actionFor(_key(LogicalKey.f1)), isNull);
    });

    test('冲突时先声明者生效并记录告警', () {
      final Keymap keymap = Keymap.fromConfig(<String, String>{
        'app.clear': 'f2',
        'help.show': 'f2',
      });
      expect(keymap.actionFor(_key(LogicalKey.f2)), KeyActions.clear);
      expect(keymap.conflicts, hasLength(1));
      expect(keymap.warnings.single, contains('app.clear'));
    });

    test('未知动作 ID 忽略并告警，不崩溃', () {
      final Keymap keymap = Keymap.fromConfig(<String, String>{
        'bogus.action': 'f3',
      });
      expect(keymap.actionFor(_key(LogicalKey.f3)), isNull);
      expect(
        keymap.warnings.any(
          (String warning) => warning.contains('bogus.action'),
        ),
        isTrue,
      );
    });

    test('同一按键可分别出现在普通表与 leader 表', () {
      final Keymap keymap = Keymap.fromConfig(<String, String>{
        'app.clear': 'm',
        'model.list': '<leader>m',
      });
      expect(keymap.labelsFor(KeyActions.clear), <String>['m']);
      expect(keymap.labelsFor(KeyActions.modelList), <String>['<leader>m']);
    });

    test('leader 不可用时 <leader> 动作被忽略', () {
      final Keymap keymap = Keymap.fromConfig(<String, String>{
        'leader': 'none',
        'session.new': '<leader>n',
      });
      expect(keymap.leader, isNull);
      expect(keymap.actionForLeaderKey(_key(LogicalKey.keyN)), isNull);
      expect(
        keymap.warnings.any(
          (String warning) => warning.contains('session.new'),
        ),
        isTrue,
      );
    });
  });
}

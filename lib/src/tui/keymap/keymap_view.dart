/// `/keybinds` 的纯文本输出：当前绑定、冲突与不可配置的局部按键边界。
library;

import 'keymap.dart';

const int _kActionWidth = 17;

/// 渲染键位表；[keymap] 由 `[keybinds]` 配置合成。
String renderKeybinds(Keymap keymap) {
  final StringBuffer buffer = StringBuffer('键位绑定（[keybinds] 可配置；none 关闭）：\n');
  buffer.writeln(
    '  ${'leader'.padRight(_kActionWidth)}'
    '${keymap.leader?.label ?? '（未绑定）'}',
  );
  for (final String action in KeyActions.ordered) {
    final List<String> labels = keymap.labelsFor(action);
    buffer.writeln(
      '  ${action.padRight(_kActionWidth)}'
      '${labels.isEmpty ? '（未绑定）' : labels.join(', ')}',
    );
  }
  _writeConflicts(buffer, keymap.conflicts);
  buffer.writeln('视图内按键（浮层 / diff / Ctrl+T / Ctrl+O）保持内置，不支持配置。');
  buffer.writeln(
    'Ctrl+Tab / Ctrl+Shift+Tab 是可配置的 tab.next / tab.previous；团队视图用 /team。',
  );
  return buffer.toString();
}

void _writeConflicts(StringBuffer buffer, List<String> conflicts) {
  if (conflicts.isEmpty) return;
  buffer.writeln('键位冲突（先声明者生效）：');
  for (final String conflict in conflicts) {
    buffer.writeln('  $conflict');
  }
}

/// 设置面板状态：分页、选中与命令映射。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

void main() {
  test('打开从第一项开始，分两页', () {
    final SettingsPrompt prompt = SettingsPrompt()..openPanel();

    expect(prompt.open, isTrue);
    expect(prompt.index, 0);
    expect(prompt.selected.title, 'Model');
    expect(prompt.page, 1);
    expect(prompt.pageCount, 2);
    expect(prompt.pageItems, hasLength(kSettingsPageSize));
  });

  test('↑↓ 移动并在两端钳制', () {
    final SettingsPrompt prompt = SettingsPrompt()..openPanel();

    prompt.move(-1);
    expect(prompt.index, 0);
    prompt.move(1);
    expect(prompt.selected.title, 'Permission');
  });

  test('←→ 翻页保留页内相对位置', () {
    final SettingsPrompt prompt = SettingsPrompt()..openPanel()
      ..move(1);

    prompt.pageBy(1);
    expect(prompt.page, 2);
    expect(prompt.selected.title, 'LSP');

    prompt.pageBy(-1);
    expect(prompt.page, 1);
    expect(prompt.selected.title, 'Permission');
  });

  test('每项映射到对应斜杠命令', () {
    final SettingsPrompt prompt = SettingsPrompt()..openPanel();

    expect(prompt.selected.command, '/model');
    prompt.move(2);
    expect(prompt.selected.command, '/theme');
  });

  test('关闭后不再拦截输入', () {
    final SettingsPrompt prompt = SettingsPrompt()..openPanel();
    prompt.close();
    expect(prompt.open, isFalse);
  });
}

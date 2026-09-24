/// shell 模式（OpenCode 式）状态机单测。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

void main() {
  test('提示文案', () {
    expect(shellInputPlaceholder(), contains('Esc'));
    expect(shellStatusHint(), contains('shell 模式'));
  });

  test('! 前缀进入并退出', () {
    final TuiShellMode shell = TuiShellMode();
    expect(shell.active, isFalse);
    expect(shell.consumeBang('!'), isTrue);
    expect(shell.active, isTrue);
    shell.exit();
    expect(shell.active, isFalse);
  });

  test('非 ! 开头不进入；已在模式内不重复吃前缀', () {
    final TuiShellMode shell = TuiShellMode();
    expect(shell.consumeBang('git status'), isFalse);
    expect(shell.active, isFalse);
    shell.enter();
    expect(shell.consumeBang('!echo hi'), isFalse);
    expect(shell.active, isTrue);
  });

  test('粘入 !cmd 也进入（消费前缀后剩 cmd）', () {
    final TuiShellMode shell = TuiShellMode();
    expect(shell.consumeBang('!ls -la'), isTrue);
    expect(shell.active, isTrue);
  });

  test('submit 退出模式并补回 ! 前缀', () {
    final TuiShellMode shell = TuiShellMode()..enter();
    expect(shell.submit('  git status  '), '!git status');
    expect(shell.active, isFalse);
  });

  test('submit 空命令不提交但仍退出模式', () {
    final TuiShellMode shell = TuiShellMode()..enter();
    expect(shell.submit('   '), isEmpty);
    expect(shell.active, isFalse);
  });

  test('!! 走控制器重跑：模式内输入 ! 提交后为 !!', () {
    final TuiShellMode shell = TuiShellMode()..enter();
    expect(shell.submit('!'), '!!');
  });
}

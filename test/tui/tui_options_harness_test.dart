import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

void main() {
  test('解析 --harness 路径', () {
    final TuiOptions options = TuiOptions.parse(const <String>[
      '--harness',
      'h/std.json',
    ]);

    expect(options.harnessPath, 'h/std.json');
  });

  test('--harness 缺值时不报错，harnessPath 为 null', () {
    final TuiOptions options = TuiOptions.parse(const <String>['--harness']);

    expect(options.harnessPath, isNull);
  });

  test('缺省不装配 harness', () {
    expect(TuiOptions.parse(const <String>[]).harnessPath, isNull);
  });

  test('用法文案提及 harness 子命令与 --harness', () {
    expect(TuiOptions.usage, contains('--harness'));
    expect(TuiOptions.usage, contains('nava harness'));
  });
}

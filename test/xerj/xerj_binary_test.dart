import 'package:conatus_code/src/xerj/xerj_binary.dart';
import 'package:test/test.dart';

void main() {
  group('XerjBinary', () {
    test('探测成功 → 使用 PATH 上的 xerj', () {
      final XerjBinary? binary = XerjBinary.discover(probe: () => true);

      expect(binary, isNotNull);
      expect(binary!.path, 'xerj');
    });

    test('探测失败 → null（工具静默不注册）', () {
      expect(XerjBinary.discover(probe: () => false), isNull);
    });
  });
}

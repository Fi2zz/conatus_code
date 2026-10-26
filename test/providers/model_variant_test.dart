/// `provider/model#variant`：接受并去掉 variant 后缀。
library;

import 'package:conatus_code/providers.dart';
import 'package:test/test.dart';

void main() {
  test('stripModelVariant / modelVariant', () {
    expect(stripModelVariant('anthropic/claude#high'), 'anthropic/claude');
    expect(stripModelVariant('anthropic/claude'), 'anthropic/claude');
    expect(modelVariant('anthropic/claude#high'), 'high');
    expect(modelVariant('anthropic/claude'), isNull);
    expect(modelVariant('anthropic/claude#'), isNull);
  });
}

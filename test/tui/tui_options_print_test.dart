/// `-p` / `--print` 与 `--output-format` 的解析：headless 入口选项。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

void main() {
  group('-p / --print', () {
    test('--print 正常取值', () {
      final TuiOptions options =
          TuiOptions.parse(const <String>['--print', '修掉 lint 错误']);
      expect(options.print, '修掉 lint 错误');
    });

    test('-p 短选项同样生效', () {
      expect(TuiOptions.parse(const <String>['-p', '跑测试']).print, '跑测试');
    });

    test('缺值视为未指定（不报错）', () {
      expect(TuiOptions.parse(const <String>['-p']).print, isNull);
    });

    test('取值以 - 开头视为缺值', () {
      expect(TuiOptions.parse(const <String>['-p', '--json']).print, isNull);
    });

    test('未出现时 print 为 null', () {
      expect(TuiOptions.parse(const <String>[]).print, isNull);
    });
  });

  group('--output-format', () {
    test('json 生效', () {
      expect(
        TuiOptions.parse(const <String>['-p', 'x', '--output-format', 'json'])
            .outputFormat,
        'json',
      );
    });

    test('非法值回落 text', () {
      expect(
        TuiOptions.parse(const <String>['--output-format', 'yaml']).outputFormat,
        'text',
      );
    });

    test('缺省 text', () {
      expect(TuiOptions.parse(const <String>[]).outputFormat, 'text');
    });
  });

  test('与 --session / --config 组合解析', () {
    final TuiOptions options = TuiOptions.parse(const <String>[
      '--session',
      'session_c8898262-4a76-4bd4-93dc-f757fd4ef666',
      '--config',
      '/tmp/a.toml',
      '-p',
      '看下 git 状态',
      '--output-format',
      'json',
    ]);

    expect(options.session, 'session_c8898262-4a76-4bd4-93dc-f757fd4ef666');
    expect(options.configPath, '/tmp/a.toml');
    expect(options.print, '看下 git 状态');
    expect(options.outputFormat, 'json');
  });

  test('usage 文案含 -p 与 --output-format', () {
    expect(TuiOptions.usage, contains('-p, --print'));
    expect(TuiOptions.usage, contains('--output-format'));
  });

  group('--version', () {
    test('出现时置 versionRequested', () {
      expect(TuiOptions.parse(const <String>['--version']).versionRequested, isTrue);
    });

    test('缺省为 false', () {
      expect(TuiOptions.parse(const <String>[]).versionRequested, isFalse);
    });
  });
}

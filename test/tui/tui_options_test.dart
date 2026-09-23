/// 入口命令行选项解析。
library;

import 'package:conatus_code/tui.dart';
import 'package:test/test.dart';

void main() {
  test('缺省：无 --session 视为新建会话', () {
    final TuiOptions options = TuiOptions.parse(const <String>[]);

    expect(options.session, isNull);
    expect(options.helpRequested, isFalse);
  });

  test('解析 --session 规范格式', () {
    final TuiOptions options = TuiOptions.parse(const <String>[
      '--session',
      'session_c8898262-4a76-4bd4-93dc-f757fd4ef666',
      '--first',
      '现在几点？',
    ]);

    expect(options.session, 'session_c8898262-4a76-4bd4-93dc-f757fd4ef666');
  });

  test('解析 --config', () {
    final TuiOptions options = TuiOptions.parse(const <String>[
      '--config',
      '/tmp/a.toml',
    ]);

    expect(options.configPath, '/tmp/a.toml');
  });

  test('未给 --config 时 configPath 为 null', () {
    expect(TuiOptions.parse(const <String>[]).configPath, isNull);
    // 尾值缺失：`--config` 后面没有取值，保持缺省。
    expect(TuiOptions.parse(const <String>['--config']).configPath, isNull);
  });

  test('--help 与 -h 都置 helpRequested，且不打断其余解析', () {
    expect(TuiOptions.parse(const <String>['--help']).helpRequested, isTrue);
    expect(TuiOptions.parse(const <String>['-h']).helpRequested, isTrue);

    final TuiOptions options = TuiOptions.parse(const <String>[
      '--session',
      'session_11111111-1111-4111-8111-111111111111',
      '--help',
    ]);

    expect(options.helpRequested, isTrue);
    expect(options.session, 'session_11111111-1111-4111-8111-111111111111');
  });

  test('--session 缺尾值视为新建会话', () {
    final TuiOptions options = TuiOptions.parse(const <String>['--session']);

    expect(options.session, isNull);
  });

  test('--session 后跟开关参数视为未指定会话，开关照常解析', () {
    final TuiOptions options = TuiOptions.parse(const <String>[
      '--session',
      '--config',
      '/tmp/a.toml',
    ]);

    expect(options.session, isNull);
    expect(options.configPath, '/tmp/a.toml');
  });

  test('--session 取值非规范格式视为新建会话，不抛错', () {
    expect(TuiOptions.parse(const <String>['--session', 'tui']).session, isNull);
    expect(
      TuiOptions.parse(const <String>['--session', 'session-1727083200-1'])
          .session,
      isNull,
    );
    expect(TuiOptions.parse(const <String>['--session', 'a b']).session, isNull);
  });

  test('未知参数忽略', () {
    final TuiOptions options = TuiOptions.parse(const <String>[
      '--unknown',
      'x',
    ]);

    expect(options.session, isNull);
  });

  test('用法文案列出全部开关', () {
    expect(TuiOptions.usage, contains('--session <id>'));
    expect(TuiOptions.usage, contains('--config <路径>'));
  });

  test('isCanonicalSessionId 识别 session_<uuid> 格式', () {
    expect(
      isCanonicalSessionId('session_c8898262-4a76-4bd4-93dc-f757fd4ef666'),
      isTrue,
    );
    // 大小写均可（UUID 十六进制）。
    expect(
      isCanonicalSessionId('session_C8898262-4A76-4BD4-93DC-F757FD4EF666'),
      isTrue,
    );
    // 非规范：缺前缀、旧格式、短 id、分叉后缀、空串。
    expect(
      isCanonicalSessionId('c8898262-4a76-4bd4-93dc-f757fd4ef666'),
      isFalse,
    );
    expect(isCanonicalSessionId('tui'), isFalse);
    expect(isCanonicalSessionId('session-1727083200123456-1'), isFalse);
    expect(isCanonicalSessionId('session_xxx'), isFalse);
    expect(
      isCanonicalSessionId(
          'session_c8898262-4a76-4bd4-93dc-f757fd4ef666-fork-1'),
      isFalse,
    );
    expect(isCanonicalSessionId(''), isFalse);
  });
}

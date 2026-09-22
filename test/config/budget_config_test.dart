import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

/// 建临时目录；用例结束即递归删除。
Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('conatus-budget');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// 把 [content] 写进临时目录的 `config.toml`，返回解析结果。
ConatusCodeConfig _load(String content) {
  final File file =
      File('${_tempDir().path}${Platform.pathSeparator}$kConfigFileName');
  file.writeAsStringSync(content);
  return loadConfig(path: file.path);
}

void main() {
  group('budget 配置', () {
    test('缺省：10 分钟墙钟 + 20 万估算 token', () {
      final String sep = Platform.pathSeparator;
      final ConatusCodeConfig config =
          loadConfig(path: '${_tempDir().path}${sep}missing.toml');

      expect(config.budget.maxTurnSeconds, 600);
      expect(config.budget.maxTurnTokens, 200000);
    });

    test('显式取值生效', () {
      final ConatusCodeConfig config = _load('[budget]\n'
          'max_turn_seconds = 300\n'
          'max_turn_tokens = 100000\n');

      expect(config.budget.maxTurnSeconds, 300);
      expect(config.budget.maxTurnTokens, 100000);
    });

    test('0 表示不限（null）', () {
      final ConatusCodeConfig config = _load('[budget]\n'
          'max_turn_seconds = 0\n'
          'max_turn_tokens = 0\n');

      expect(config.budget.maxTurnSeconds, isNull);
      expect(config.budget.maxTurnTokens, isNull);
    });

    test('负数或类型不符 → ConfigException', () {
      expect(
        () => _load('[budget]\nmax_turn_seconds = -1\n'),
        throwsA(isA<ConfigException>().having(
            (ConfigException error) => error.message, 'message',
            contains('max_turn_seconds 必须是非负整数'))),
      );
      expect(
        () => _load('[budget]\nmax_turn_tokens = "big"\n'),
        throwsA(isA<ConfigException>().having(
            (ConfigException error) => error.message, 'message',
            contains('max_turn_tokens 必须是非负整数'))),
      );
    });
  });
}

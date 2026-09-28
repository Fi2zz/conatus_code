/// `[llm]` 韧性配置的解析：`fallback_models` 与退避重试参数。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 建临时目录；用例结束即递归删除。
Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('conatus-llm-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// 把 [content] 写成临时 `config.toml` 并解析。
ConatusCodeConfig parseConfig(String content) {
  final File file = File(
    '${_tempDir().path}${Platform.pathSeparator}$kConfigFileName',
  );
  file.writeAsStringSync(content);
  return loadConfig(path: file.path);
}

void main() {
  group('fallback_models', () {
    test('缺省为空（不配就没有回退）', () {
      final ConatusCodeConfig config = parseConfig('''
        [llm]
        default_model = "ark/doubao"
      ''');
      expect(config.llm.fallbackModels, isEmpty);
    });

    test('读成有序清单', () {
      final ConatusCodeConfig config = parseConfig('''
        [llm]
        default_model = "ark/doubao"
        fallback_models = ["deepseek/chat", "openai/gpt-4o-mini"]
      ''');
      expect(config.llm.fallbackModels,
          <String>['deepseek/chat', 'openai/gpt-4o-mini']);
    });

    test('去掉首尾空白，空串项直接丢弃', () {
      final ConatusCodeConfig config = parseConfig('''
        [llm]
        fallback_models = [" deepseek/chat ", "", "   "]
      ''');
      expect(config.llm.fallbackModels, <String>['deepseek/chat']);
    });

    test('缺少斜杠的项报错并指出是哪一条', () {
      expect(
        () => parseConfig('''
          [llm]
          fallback_models = ["deepseek/chat", "nonsense"]
        '''),
        throwsA(isA<ConfigException>()
            .having((ConfigException e) => e.message, 'message',
                allOf(contains('nonsense'), contains('provider/model')))),
      );
    });

    test('非字符串数组报错', () {
      expect(
        () => parseConfig('''
          [llm]
          fallback_models = [1, 2]
        '''),
        throwsA(isA<ConfigException>()),
      );
    });
  });

  group('退避重试参数', () {
    test('缺省为 4 次 / 500ms / 30s', () {
      final ConatusCodeConfig config = parseConfig('''
        [llm]
        default_model = "ark/doubao"
      ''');
      expect(config.llm.retry.maxAttempts, 4);
      expect(config.llm.retry.baseDelayMs, 500);
      expect(config.llm.retry.maxDelayMs, 30000);
    });

    test('可覆盖', () {
      final ConatusCodeConfig config = parseConfig('''
        [llm]
        max_attempts = 6
        retry_base_ms = 250
        retry_max_ms = 8000
      ''');
      expect(config.llm.retry.maxAttempts, 6);
      expect(config.llm.retry.baseDelayMs, 250);
      expect(config.llm.retry.maxDelayMs, 8000);
    });

    test('max_attempts = 1 表示关闭重试', () {
      final ConatusCodeConfig config = parseConfig('''
        [llm]
        max_attempts = 1
      ''');
      expect(config.llm.retry.toPolicy().maxAttempts, 1);
    });

    test('负数报错', () {
      expect(
        () => parseConfig('''
          [llm]
          max_attempts = -1
        '''),
        throwsA(isA<ConfigException>()),
      );
    });

    test('toPolicy 换算成毫秒', () {
      const RetrySettings settings =
          RetrySettings(maxAttempts: 3, baseDelayMs: 200, maxDelayMs: 5000);
      final RetryPolicy policy = settings.toPolicy();
      expect(policy.maxAttempts, 3);
      expect(policy.baseDelay, const Duration(milliseconds: 200));
      expect(policy.maxDelay, const Duration(seconds: 5));
    });
  });
}

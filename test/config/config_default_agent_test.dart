/// `[agent] default_agent` 配置：缺省 build、显式值原样保留。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

/// 把 [toml] 写进临时目录的 `config.toml` 并加载。
ConatusCodeConfig loadConfigFromToml(String toml) {
  final Directory dir = Directory.systemTemp.createTempSync(
    'nava-agent-config',
  );
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}${Platform.pathSeparator}$kConfigFileName')
    ..writeAsStringSync(toml);
  return loadConfig(path: file.path);
}

void main() {
  test('缺省默认 Agent 是 build', () {
    final ConatusCodeConfig config = loadConfigFromToml('');

    expect(config.agent.defaultAgent, 'build');
  });

  test('[agent] default_agent selects the default', () {
    final ConatusCodeConfig config = loadConfigFromToml(
      '[agent]\ndefault_agent = "plan"',
    );

    expect(config.agent.defaultAgent, 'plan');
  });

  test('default_agent 为空串时回退 build', () {
    final ConatusCodeConfig config = loadConfigFromToml(
      '[agent]\ndefault_agent = ""',
    );

    expect(config.agent.defaultAgent, 'build');
  });

  test('default_agent 必须是字符串', () {
    expect(
      () => loadConfigFromToml('[agent]\ndefault_agent = 3'),
      throwsA(
        isA<ConfigException>().having(
          (ConfigException error) => error.message,
          'message',
          contains('default_agent'),
        ),
      ),
    );
  });
}

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

/// 把 [content] 写进临时目录的 `config.toml`，返回解析结果。
ConatusCodeConfig _load(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('conatus-subperm');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}${Platform.pathSeparator}$kConfigFileName');
  file.writeAsStringSync(content);
  return loadConfig(path: file.path);
}

void main() {
  group('子代理权限模式配置', () {
    test('缺省 inherit', () {
      final ConatusCodeConfig config = _load('');
      expect(config.agent.subagentPermission, 'inherit');
    });

    test('显式取值生效', () {
      final ConatusCodeConfig config = _load('[agent]\n'
          'subagent_permission = "readonly"\n');
      expect(config.agent.subagentPermission, 'readonly');
    });

    test('非法值报 ConfigException', () {
      expect(
        () => _load('[agent]\nsubagent_permission = "yolo"\n'),
        throwsA(isA<ConfigException>()),
      );
    });
  });
}

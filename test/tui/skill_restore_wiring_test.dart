/// runtime 装配：启动时把记忆里已持久化的技能恢复成工具。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync(
    'nava-skill-restore',
  );
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void main() {
  test('restore 把记忆里的技能注册回工具表', () async {
    final Directory temp = _tempDir();
    final Directory work = _tempDir();
    final String skill = jsonEncode(<String, Object?>{
      'name': 'report_time',
      'description': '复述当前时间',
      'steps': <Object?>[
        <String, Object?>{
          'toolName': 'get_time',
          'arguments': <String, Object?>{},
        },
      ],
    });
    File('${temp.path}/memory.json').writeAsStringSync(
      jsonEncode(<Object?>[
        <String, Object?>{
          'id': 'skill-1',
          'text': skill,
          'tags': <String>['skill'],
          'createdAt': DateTime.now().toIso8601String(),
        },
      ]),
    );

    final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
      baseDir: temp.path,
      workdir: work.path,
      sessionDir: '${temp.path}/sessions',
      memoryFile: '${temp.path}/memory.json',
      webTools: false,
      skills: false,
      llm: FallbackLlm(const <LlmProvider>[]),
      interactive: false,
    );
    addTearDown(runtime.dispose);

    final ToolRegistry tools = runtime.app.require<ToolRegistry>('tools');
    expect(tools.get('report_time'), isNotNull);
  });

  test('记忆文件损坏不影响启动', () async {
    final Directory temp = _tempDir();
    final Directory work = _tempDir();
    File('${temp.path}/memory.json').writeAsStringSync('{ not json');

    final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
      baseDir: temp.path,
      workdir: work.path,
      sessionDir: '${temp.path}/sessions',
      memoryFile: '${temp.path}/memory.json',
      webTools: false,
      skills: false,
      llm: FallbackLlm(const <LlmProvider>[]),
      interactive: false,
    );
    addTearDown(runtime.dispose);

    expect(
      runtime.app.require<ToolRegistry>('tools').get('report_time'),
      isNull,
    );
  });
}

/// runtime 装配：`bootstrap_skills` 把技能正文接进 system prompt。
library;

import 'dart:io';

import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-bootstrap');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void _writeSkill(Directory root, String name, String body) {
  final Directory dir = Directory('${root.path}${Platform.pathSeparator}$name')
    ..createSync(recursive: true);
  File(
    '${dir.path}${Platform.pathSeparator}SKILL.md',
  ).writeAsStringSync('---\nname: $name\ndescription: 启动技能。\n---\n$body');
}

void main() {
  test('bootstrap_skills 注入技能正文与 nava 工具映射', () async {
    final Directory temp = _tempDir();
    final Directory skills = _tempDir();
    final Directory work = _tempDir();
    _writeSkill(skills, 'using-superpowers', '行动前先检查技能。');
    final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
      baseDir: temp.path,
      workdir: work.path,
      sessionDir: '${temp.path}/sessions',
      memoryFile: '${temp.path}/memory.json',
      webTools: false,
      extraSkillDirs: <String>[skills.path],
      bootstrapSkills: const <String>['using-superpowers'],
      llm: FallbackLlm(const <LlmProvider>[]),
      interactive: false,
    );
    addTearDown(runtime.dispose);

    final SystemPrompt prompt = runtime.app.require<SystemPrompt>(
      'systemPrompt',
    );
    final String text = prompt.render(prompt.assemble());

    expect(text, contains('行动前先检查技能。'));
    expect(text, contains('Tool Mapping for nava'));
    expect(text, contains('ALREADY LOADED'));
  });
}

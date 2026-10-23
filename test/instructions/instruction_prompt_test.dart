/// `InstructionPrompt`：按内容懒注册 `project` 段，每次 assemble 重新加载。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

final String _sep = Platform.pathSeparator;

void main() {
  late Directory dir;
  late InstructionLoader loader;
  late SystemPrompt prompt;
  late InstructionPrompt instructionPrompt;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-instr-prompt-');
    loader = InstructionLoader(
      workdir: dir.path,
      home: '${dir.path}${_sep}home',
    );
    prompt = SystemPrompt();
    instructionPrompt = InstructionPrompt(loader: loader, prompt: prompt);
  });

  tearDown(() {
    loader.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('启动无文件时不注册空段', () async {
    await instructionPrompt.start();

    expect(
      prompt.sections.map((PromptSection section) => section.name),
      isNot(contains('project')),
    );
  });

  test('启动有文件时注册，refresh 后文本更新', () async {
    File('${dir.path}${_sep}AGENTS.md').writeAsStringSync('FIRST');
    await instructionPrompt.start();
    expect(
      prompt.sections.map((PromptSection section) => section.name),
      contains('project'),
    );
    expect(prompt.render(prompt.assemble()), contains('FIRST'));

    File('${dir.path}${_sep}sub${_sep}AGENTS.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('SECOND');
    await loader.notePath('${dir.path}${_sep}sub${_sep}a.dart');
    await instructionPrompt.refresh();

    final String rendered = prompt.render(prompt.assemble());
    expect(rendered, contains('SECOND'));
    expect(rendered.indexOf('FIRST'), lessThan(rendered.indexOf('SECOND')));
  });
}

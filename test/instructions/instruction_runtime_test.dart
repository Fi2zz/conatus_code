/// TUI 装配：`'instructions'` 服务、`project` 段与工具后置发现。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

final String _sep = Platform.pathSeparator;

String _write(String base, List<String> parts, String content) {
  final String path = <String>[base, ...parts].join(_sep);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
  return path;
}

Future<ConatusTuiRuntime> _boot(
  String workdir,
  String home, {
  List<String> instructions = const <String>[],
}) => ConatusTuiRuntime.create(
  baseDir: workdir,
  sessionDir: workdir,
  memoryFile: '$workdir$_sep.memory.json',
  workdir: workdir,
  instructionHome: home,
  webTools: false,
  skills: false,
  llm: FallbackLlm(const <LlmProvider>[]),
  instructions: instructions,
);

String? _projectText(ConatusTuiRuntime runtime) {
  final SystemPrompt prompt = runtime.app.require<SystemPrompt>('systemPrompt');
  for (final PromptSection section in prompt.sections) {
    if (section.name == 'project') return section.text();
  }
  return null;
}

void main() {
  late Directory dir;
  late Directory home;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-instr-runtime-');
    home = Directory.systemTemp.createTempSync('nava-instr-home-');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  test('启动时装配 instructions 来源并注册 project 段', () async {
    _write(dir.path, <String>['extra.md'], 'CONFIG-EXTRA');
    final ConatusTuiRuntime runtime = await _boot(
      dir.path,
      home.path,
      instructions: const <String>['extra.md'],
    );
    addTearDown(runtime.dispose);

    expect(runtime.app.get<InstructionLoader>('instructions'), isNotNull);
    expect(_projectText(runtime), contains('CONFIG-EXTRA'));
  });

  test('read 后下一轮 project 段包含嵌套 AGENTS.md', () async {
    final String nested = <String>[dir.path, 'pkg'].join(_sep);
    _write(nested, <String>['AGENTS.md'], 'RUNTIME-NESTED');
    final String file = _write(nested, <String>['a.dart'], 'void main() {}');
    final ConatusTuiRuntime runtime = await _boot(dir.path, home.path);
    addTearDown(runtime.dispose);

    // 用户级全局文件不参与：假 home 为空，project 段此刻不该存在。
    expect(_projectText(runtime), isNull);

    final ToolResult result = await runtime.tools.call(
      ToolCall(name: 'read', arguments: <String, Object?>{'path': file}),
    );

    expect(result.isError, isFalse);
    expect(_projectText(runtime), contains('RUNTIME-NESTED'));
  });
}

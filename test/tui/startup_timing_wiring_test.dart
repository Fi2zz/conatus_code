/// 启动耗时采样器的装配接线：runtime 打「装配完成」、控制器转发「首帧」。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

Future<(ConatusTuiRuntime, StartupTiming)> _create() async {
  final Directory dir = Directory.systemTemp.createTempSync('nava-startup');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String sep = Platform.pathSeparator;
  final StartupTiming timing = StartupTiming()..markConfigLoaded();
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    baseDir: dir.path,
    sessionDir: dir.path,
    memoryFile: '${dir.path}${sep}memory.json',
    webTools: false,
    skills: false,
    llm: FallbackLlm(const <LlmProvider>[]),
    startupTiming: timing,
  );
  addTearDown(runtime.dispose);
  return (runtime, timing);
}

void main() {
  test('create 把采样器放进上下文，并在装配完成时打点', () async {
    final (ConatusTuiRuntime runtime, StartupTiming timing) = await _create();

    expect(
      identical(runtime.app.get<StartupTiming>('startupTiming'), timing),
      isTrue,
    );
    expect(timing.describe(), contains('装配 '));
  });

  test('控制器转发首帧打点：打完不再标「首帧未记录」', () async {
    final (ConatusTuiRuntime runtime, StartupTiming timing) = await _create();
    final ConatusTuiController controller = runtime.createController(
      onExit: () {},
    );
    expect(timing.describe(), contains('首帧未记录'));

    controller.markFirstFrame();

    expect(timing.describe(), isNot(contains('首帧未记录')));
  });
}

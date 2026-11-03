/// 首帧后装配：文件工具 / 技能 / 检查点延后，首轮请求前等齐。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_skill/conatus_skill.dart';
import 'package:test/test.dart';

class _CaptureProvider implements LlmProvider {
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];

  @override
  String get name => 'capture';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(messages);
    return const LlmResult(content: '好的', provider: 'capture', model: 'm');
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

Future<(ConatusTuiRuntime, _CaptureProvider)> _create({
  bool defer = true,
}) async {
  final Directory dir = Directory.systemTemp.createTempSync('nava-defer');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String sep = Platform.pathSeparator;
  final _CaptureProvider provider = _CaptureProvider();
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    baseDir: dir.path,
    sessionDir: dir.path,
    memoryFile: '${dir.path}${sep}memory.json',
    workdir: dir.path,
    webTools: false,
    llm: FallbackLlm(<LlmProvider>[provider]),
    checkpoint: const CheckpointConfig(keep: 3),
    deferStartup: defer,
  );
  addTearDown(runtime.dispose);
  return (runtime, provider);
}

void main() {
  test('deferStartup：首帧前没有文件工具 / 技能 / 检查点', () async {
    final (ConatusTuiRuntime runtime, _) = await _create();

    expect(runtime.deferredStartup, isNotNull);
    expect(runtime.tools.get('read'), isNull);
    expect(runtime.app.get<SkillRegistry>('skillRegistry'), isNull);
    expect(runtime.app.get<CheckpointManager>('checkpointManager'), isNull);

    await runtime.deferredStartup!.start();

    expect(runtime.tools.get('read'), isNotNull);
    expect(runtime.app.get<SkillRegistry>('skillRegistry'), isNotNull);
    expect(runtime.app.get<CheckpointManager>('checkpointManager'), isNotNull);
  });

  test('deferStartup=false：装配返回时一切就绪', () async {
    final (ConatusTuiRuntime runtime, _) = await _create(defer: false);

    expect(runtime.deferredStartup, isNull);
    expect(runtime.tools.get('read'), isNotNull);
    expect(runtime.app.get<SkillRegistry>('skillRegistry'), isNotNull);
    expect(runtime.app.get<CheckpointManager>('checkpointManager'), isNotNull);
  });

  test('首轮请求等后置装配完成才调用模型', () async {
    final (ConatusTuiRuntime runtime, _CaptureProvider provider) = await _create();
    final ConatusTuiController controller = runtime.createController(
      onExit: () {},
    );
    await controller.start();

    final Future<void> turn = controller.submit('你好');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(provider.calls, isEmpty, reason: '后置装配未完成时不该先发请求');

    await turn;
    expect(provider.calls, isNotEmpty);
    expect(runtime.tools.get('read'), isNotNull);
  });
}

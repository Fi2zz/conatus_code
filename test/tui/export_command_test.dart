/// `/export` 命令端到端：真实控制器 + 真实落盘。
library;

import 'dart:io';

import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _EchoProvider implements LlmProvider {
  @override
  String get name => 'echo';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      const LlmResult(content: '已完成。', provider: 'echo', model: 'm');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

Future<(ConatusTuiController, Context)> _launch(
  Context app,
  SessionStore sessions,
) async {
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'testprov/m1',
    onExit: () {},
  );
  await controller.start();
  return (controller, app);
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-export-e2e');
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  Context newApp(String? workdir) {
    final Context app = Context.root();
    addTearDown(app.dispose);
    provideTools(app);
    provideFileSystemLocal(app);
    provideShellLocal(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_EchoProvider()]));
    if (workdir != null) app.provide('workdir', workdir);
    return app;
  }

  test('导出到指定路径并提示绝对路径', () async {
    final Context app = newApp(dir.path);
    final SessionStore sessions = provideSessions(app);
    final (ConatusTuiController controller, _) = await _launch(app, sessions);
    await controller.handleLine('做件事');

    final String target = '${dir.path}${Platform.pathSeparator}out.md';
    await controller.handleLine('/export $target');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('已导出'));
    expect(text, contains(target));
    expect(File(target).existsSync(), isTrue);
    expect(File(target).readAsStringSync(), contains('做件事'));
    expect(File(target).readAsStringSync(), contains('已完成。'));
  });

  test('缺省落项目数据目录的 exports/', () async {
    final Context app = newApp(dir.path);
    final SessionStore sessions = provideSessions(app);
    final (ConatusTuiController controller, _) = await _launch(app, sessions);
    await controller.handleLine('做件事');

    await controller.handleLine('/export');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('已导出'));
    // 未给路径时按 <projectDataDir> 解析，落在 exports/ 下。
    expect(text, contains('exports'));
  });

  test('导出内容不含「导出」这条记录本身', () async {
    final Context app = newApp(dir.path);
    final SessionStore sessions = provideSessions(app);
    final (ConatusTuiController controller, _) = await _launch(app, sessions);
    await controller.handleLine('做件事');

    final String target = '${dir.path}${Platform.pathSeparator}out.md';
    await controller.handleLine('/export $target');

    final String md = File(target).readAsStringSync();
    expect(md.contains('## 你'), isTrue);
    // 导出只写会话事件，不写屏上 system 消息。
    expect(md.contains('已导出'), isFalse);
  });

  test('落点不可写时给出错误而不是未捕获异常', () async {
    final Context app = newApp(dir.path);
    final SessionStore sessions = provideSessions(app);
    final (ConatusTuiController controller, _) = await _launch(app, sessions);

    // 拿一个已存在的目录当文件写，必失败。
    final Directory occupied =
        Directory('${dir.path}${Platform.pathSeparator}blocked')
          ..createSync();
    await controller.handleLine('/export ${occupied.path}');

    expect(controller.transcript.messages.last.text, contains('导出失败'));
  });

  test('命令表包含 export', () {
    expect(tuiCommands.any((TuiCommand c) => c.name == 'export'), isTrue);
  });
}

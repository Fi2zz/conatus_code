/// `/init` 命令：让模型生成 / 更新项目 AGENTS.md。
library;

import 'dart:io';

import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 记录实际收到的用户输入并回一句固定回复。
class _InitCaptureProvider implements LlmProvider {
  final List<String> prompts = <String>[];

  @override
  String get name => 'capture';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final String last = messages.last.content;
    prompts.add(last);
    return const LlmResult(content: '已生成 AGENTS.md。', provider: 's', model: 'm');
  }

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

Future<(ConatusTuiController, Context, _InitCaptureProvider)> _build(
    String workdir) async {
  final Context app = Context.root();
  provideTools(app);
  final _InitCaptureProvider provider = _InitCaptureProvider();
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[provider]));
  final SessionStore sessions = provideSessions(app);
  app.provide('workdir', workdir);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    onExit: () {},
  );
  await controller.start();
  return (controller, app, provider);
}

void main() {
  test('/init 提交生成提示词（文件不存在分支）', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('nava-init');
    addTearDown(() => dir.deleteSync(recursive: true));
    final (ConatusTuiController controller, Context app, _InitCaptureProvider p) =
        await _build(dir.path);
    addTearDown(app.dispose);

    await controller.handleLine('/init');

    expect(p.prompts.single, contains('生成 AGENTS.md'));
    expect(p.prompts.single, contains('write_file 创建'));
    expect(p.prompts.single, contains('文件不存在'));
  });

  // 校验命令写进 AGENTS.md，模型交付前自己跑——这是不引入语言服务器前提下
  // 拿到诊断反馈的路径（对比：LSP 需要常驻进程 + 用户装服务器 + 内存代价）。
  test('/init 提示词要求写明交付前的校验命令', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('nava-init');
    addTearDown(() => dir.deleteSync(recursive: true));
    final (ConatusTuiController controller, Context app, _InitCaptureProvider p) =
        await _build(dir.path);
    addTearDown(app.dispose);

    await controller.handleLine('/init');

    expect(p.prompts.single, contains('诊断与自检命令'));
    expect(p.prompts.single, contains('交付前'));
    expect(p.prompts.single, contains('CI 配置'));
    // 校验命令要来自仓库自身，别让模型凭空编一条。
    expect(p.prompts.single, contains('不要凭空编'));
  });

  test('/init 已存在 AGENTS.md 时提示更新分支', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('nava-init');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}${Platform.pathSeparator}AGENTS.md')
        .writeAsStringSync('# 旧内容\n');
    final (ConatusTuiController controller, Context app, _InitCaptureProvider p) =
        await _build(dir.path);
    addTearDown(app.dispose);

    await controller.handleLine('/init');

    expect(
      controller.transcript.messages
          .any((TuiMessage m) => m.text.contains('先读取再更新')),
      isTrue,
    );
    expect(p.prompts.single, contains('先读取再改写'));
  });

  test('命令表包含 init', () {
    final TuiCommand init =
        tuiCommands.firstWhere((TuiCommand c) => c.name == 'init');
    expect(init.description, contains('AGENTS.md'));
  });
}

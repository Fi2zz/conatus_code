/// story 装配开关：默认关闭时直写、开启时待定补丁、审阅门先于审批门。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/fs_tools.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _StubProvider implements LlmProvider {
  @override
  String get name => 'stub';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async => const LlmResult(content: 'ok', provider: 'stub', model: 'm');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

Future<(ConatusTuiController, Context, Directory)> _buildController({
  required bool storyEnabled,
}) async {
  final Directory dir =
      Directory.systemTemp.createTempSync('nava-story-wiring-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final Context app = Context.root();
  provideTools(app);
  final FileSystem fs = provideFileSystemLocal(
    app,
    fs: LocalFileSystem(cwd: dir.path),
  );
  provideFsTools(app, fs: fs, enableSearch: false);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
  provideSessionLog(app, log: InMemorySessionLog());
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    initialSession: 's1',
    modelLabel: 'stub',
    storyEnabled: storyEnabled,
    onExit: () {},
  );
  await controller.start();
  return (controller, app, dir);
}

void main() {
  test('story 关闭：write 直接落盘', () async {
    final (ConatusTuiController _, Context app, Directory dir) =
        await _buildController(storyEnabled: false);

    final ToolResult result = await app.tools.call(
      const ToolCall(
        name: 'write',
        arguments: <String, Object?>{'path': 'a.txt', 'content': 'hello'},
      ),
    );

    expect(result.isError, isFalse);
    expect(result.content, isNot(contains('待定补丁')));
    expect(File('${dir.path}/a.txt').readAsStringSync(), 'hello');
  });

  test('story 开启：write 成待定补丁，apply 后落盘', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _buildController(storyEnabled: true);

    final ToolResult result = await app.tools.call(
      const ToolCall(
        name: 'write',
        arguments: <String, Object?>{'path': 'a.txt', 'content': 'hello'},
      ),
    );

    expect(result.isError, isFalse);
    expect(result.content, contains('待定补丁'));
    expect(File('${dir.path}/a.txt').existsSync(), isFalse);

    await controller.handleLine('/story apply 1');
    expect(File('${dir.path}/a.txt').readAsStringSync(), 'hello');
  });

  test('/story apply 的 IO 失败给出系统提示，不抛未处理异常', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _buildController(storyEnabled: true);
    File('${dir.path}/a.txt').writeAsStringSync('old');
    await app.tools.call(
      const ToolCall(
        name: 'write',
        arguments: <String, Object?>{
          'path': 'a.txt',
          'content': 'hello',
          'mode': 'overwrite',
        },
      ),
    );
    // 目录只读：apply 的原子写必然失败，用于验证命令层兜住 IO 异常。
    await Process.run('chmod', <String>['500', dir.path]);

    await controller.handleLine('/story apply 1');
    await Process.run('chmod', <String>['700', dir.path]);

    expect(
      controller.transcript.messages.last.text,
      contains('故事操作失败'),
    );
  });

  test('审阅门先于审批门：写工具不触发审批', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('nava-story-gate-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final Context ctx = Context.root();
    provideTools(ctx);
    final FileSystem fs = provideFileSystemLocal(
      ctx,
      fs: LocalFileSystem(cwd: dir.path),
    );
    provideFsTools(ctx, fs: fs, enableSearch: false);
    provideSessionLog(ctx, log: InMemorySessionLog());
    final SessionStore sessions = provideSessions(ctx);
    final Session session = sessions.create();
    await provideStory(
      ctx,
      sessionId: session.id,
      session: session,
      review: true,
    );
    final AutoApproval approval = AutoApproval(true);
    instrumentApproval(ctx, approval: approval, threshold: ToolRisk.medium);

    final ToolResult result = await ctx.tools.call(
      const ToolCall(
        name: 'write',
        arguments: <String, Object?>{'path': 'a.txt', 'content': 'hello'},
      ),
    );

    expect(approval.requests, 0);
    expect(result.isError, isFalse);
    expect(result.content, contains('待定补丁'));
  });

  test('headless（interactive=false）不注入交互式故事 prompt', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('nava-story-prompt-');
    addTearDown(() => dir.deleteSync(recursive: true));
    Future<ConatusTuiRuntime> build(bool interactive) =>
        ConatusTuiRuntime.create(
          baseDir: dir.path,
          webTools: false,
          skills: false,
          interactive: interactive,
          llm: FallbackLlm(<LlmProvider>[_StubProvider()]),
          story: const StoryConfig(enabled: true),
        );

    final ConatusTuiRuntime headless = await build(false);
    addTearDown(headless.dispose);
    final SystemPrompt headlessPrompt =
        headless.app.get<SystemPrompt>('systemPrompt')!;
    expect(
      headlessPrompt.sections.map((PromptSection s) => s.name),
      isNot(contains('story-ops')),
    );

    final ConatusTuiRuntime tui = await build(true);
    addTearDown(tui.dispose);
    final SystemPrompt tuiPrompt = tui.app.get<SystemPrompt>('systemPrompt')!;
    expect(
      tuiPrompt.sections.map((PromptSection s) => s.name),
      contains('story-ops'),
    );
  });

  test('运行时按开关装配 story-log 服务', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('nava-story-runtime-');
    addTearDown(() => dir.deleteSync(recursive: true));
    Future<ConatusTuiRuntime> build(bool enabled) => ConatusTuiRuntime.create(
          baseDir: dir.path,
          webTools: false,
          skills: false,
          interactive: false,
          llm: FallbackLlm(<LlmProvider>[_StubProvider()]),
          story: StoryConfig(enabled: enabled),
        );

    final ConatusTuiRuntime off = await build(false);
    addTearDown(off.dispose);
    expect(off.app.get<SessionLog>('sessionLog'), isNull);

    final ConatusTuiRuntime on = await build(true);
    addTearDown(on.dispose);
    expect(on.app.get<SessionLog>('sessionLog'), isNotNull);
  });
}

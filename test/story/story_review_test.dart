/// 事前审阅门：写工具拦成待定补丁（不落盘）、fail-open 放行、链上先于
/// 审批命中、apply/reject 出口、headless（无控制器挂载）不拦截。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/fs_tools.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_doc/conatus_doc.dart';
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

/// 审批探针：任何审批请求都计数并拒绝（被调用即说明审查门没拦住）。
class _SpyGate extends TuiPermissionGate {
  _SpyGate() : super(choice: TuiChoicePrompt());

  int requests = 0;

  @override
  Future<bool> request(ApprovalRequest request) async {
    requests++;
    return false;
  }
}

/// gate 单测装配：注册表 + 真写工具 + fs 临时目录 + pending + 内存引擎。
(ToolRegistry, StoryPending, DocEngine, Directory) _buildGate() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-review-');
  final FileSystem fs = LocalFileSystem(cwd: dir.path);
  final ToolRegistry tools = ToolRegistry()
    ..register(WriteFileTool(fs: fs))
    ..register(EditFileTool(fs: fs))
    ..register(ApplyPatchTool(fs: fs));
  final StoryPending pending = StoryPending();
  final DocEngine engine = DocEngine(PatchLog(), sessionId: 's1');
  StoryReviewGate(pending: pending, fs: fs).mount(tools);
  return (tools, pending, engine, dir);
}

void main() {
  group('StoryReviewGate 拦截', () {
    test('write 被拦：文件未落盘、结果非错误、pending +1', () async {
      final (tools, pending, _, Directory dir) = _buildGate();
      addTearDown(() => dir.deleteSync(recursive: true));

      final ToolResult result = await tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'a.md', 'content': '待定内容'},
        ),
      );

      expect(result.isError, isFalse);
      expect(result.content, contains('待定补丁 #1'));
      expect(result.content, contains('无需重试'));
      expect(File('${dir.path}/a.md').existsSync(), isFalse);
      expect(pending.patches.single.ops.single, isA<InsertBlockOp>());
      expect(pending.sources.values.single, 'write');
    });

    test('审查门在审批位（内层探针）之前命中：拦截后审批不触发', () async {
      // 链顺序实证：先注册者在外层先命中（probe 探针在 story_review 单测
      // 链路上验证过 first-registered 先执行）。_buildGate 先挂审查门
      // （story 位，_bind 时早于审批挂载），这里的探针后挂——模拟审批位
      // （_syncPermissionMode 晚注册 = 内层）：拦截后 next() 不被调用。
      final (tools, pending, _, Directory dir) = _buildGate();
      addTearDown(() => dir.deleteSync(recursive: true));
      int probed = 0;
      tools.use((ToolCall call, Future<ToolResult> Function() next) async {
        probed++;
        return next();
      });

      await tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'a.md', 'content': 'x'},
        ),
      );

      expect(probed, 0);
      expect(pending.patches.length, 1);
    });

    test('edit 的 old 串找不到 → fail-open 放行，真实错误回到模型', () async {
      final (tools, pending, _, Directory dir) = _buildGate();
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/a.md').writeAsStringSync('实际内容');

      final ToolResult result = await tools.call(
        const ToolCall(
          name: 'edit',
          arguments: <String, Object?>{
            'path': 'a.md',
            'old_string': '不存在的串',
            'new_string': 'x',
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(result.error?.code, 'FS_NOT_FOUND');
      expect(pending.patches, isEmpty);
    });

    test('apply_patch 多文件 → 一条待定补丁（多个 op），文件未落盘', () async {
      final (tools, pending, _, Directory dir) = _buildGate();
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/a.txt').writeAsStringSync('l1\n');
      File('${dir.path}/b.txt').writeAsStringSync('m1\n');
      const String patch = '''
--- a/a.txt
+++ b/a.txt
@@ -1,1 +1,1 @@
-l1
+l2
--- a/b.txt
+++ b/b.txt
@@ -1,1 +1,1 @@
-m1
+m2
''';

      final ToolResult result = await tools.call(
        const ToolCall(
          name: 'apply_patch',
          arguments: <String, Object?>{'patch': patch},
        ),
      );

      expect(result.isError, isFalse);
      expect(result.content, contains('2 个文件'));
      expect(pending.patches.single.ops.length, 2);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'l1\n');
    });

    test('无 fs 缝时全部放行（headless 等价路径：不挂载即不拦截）', () async {
      final Directory dir = Directory.systemTemp.createTempSync(
        'nava-review-open-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final FileSystem fs = LocalFileSystem(cwd: dir.path);
      final ToolRegistry tools = ToolRegistry()
        ..register(WriteFileTool(fs: fs));
      // 不挂审查门（headless 不经控制器 _syncPermissionMode）。
      final ToolResult result = await tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'direct.md', 'content': '直写'},
        ),
      );

      expect(result.isError, isFalse);
      expect(File('${dir.path}/direct.md').readAsStringSync(), '直写');
    });
  });

  group('控制器端到端', () {
    test('write 拦成待定补丁（审批不弹）→ /story pending 显示来源 → '
        'apply 落盘入故事', () async {
      final Directory dir = Directory.systemTemp.createTempSync(
        'nava-review-e2e-',
      );
      final Context app = Context.root();
      provideTools(app);
      provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
      provideFileSystemLocal(app, fs: LocalFileSystem(cwd: dir.path));
      provideFsTools(app, enableSearch: false);
      final _SpyGate spy = _SpyGate();
      app.provide('approval', spy);
      final SessionStore sessions = provideSessions(app);
      final ConatusTuiController controller = ConatusTuiController(
        app: app,
        sessions: sessions,
        name: 'test',
        modelLabel: 'mock',
        storyEnabled: true,
        onExit: () {},
      );
      addTearDown(() {
        app.dispose();
        dir.deleteSync(recursive: true);
      });
      await controller.start();

      final ToolResult result = await app.tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'ch1.md', 'content': '第一章'},
        ),
      );
      expect(result.isError, isFalse);
      expect(spy.requests, 0); // 审批未触发
      expect(controller.choice.open, isFalse);
      expect(File('${dir.path}/ch1.md').existsSync(), isFalse);

      await controller.handleLine('/story pending');
      final String list = controller.transcript.messages.last.text;
      expect(list, contains('[write]'));
      expect(list, contains('ch1.md'));

      await controller.handleLine('/story apply 1');
      expect(File('${dir.path}/ch1.md').readAsStringSync(), '第一章');
      await controller.handleLine('/story');
      expect(controller.transcript.messages.last.text, contains('1 个补丁'));
      await controller.handleLine('/story pending');
      expect(controller.transcript.messages.last.text, contains('没有待定补丁'));
    });

    test('/story reject 丢弃待定补丁，文件不变', () async {
      final Directory dir = Directory.systemTemp.createTempSync(
        'nava-review-rej-',
      );
      final Context app = Context.root();
      provideTools(app);
      provideLlm(app, llm: FallbackLlm(<LlmProvider>[_StubProvider()]));
      provideFileSystemLocal(app, fs: LocalFileSystem(cwd: dir.path));
      provideFsTools(app, enableSearch: false);
      final SessionStore sessions = provideSessions(app);
      final ConatusTuiController controller = ConatusTuiController(
        app: app,
        sessions: sessions,
        name: 'test',
        modelLabel: 'mock',
        storyEnabled: true,
        onExit: () {},
      );
      addTearDown(() {
        app.dispose();
        dir.deleteSync(recursive: true);
      });
      await controller.start();
      await app.tools.call(
        const ToolCall(
          name: 'write',
          arguments: <String, Object?>{'path': 'ch2.md', 'content': '待定'},
        ),
      );

      await controller.handleLine('/story reject 1');

      expect(controller.transcript.messages.last.text, contains('已丢弃'));
      expect(File('${dir.path}/ch2.md').existsSync(), isFalse);
      await controller.handleLine('/story pending');
      expect(controller.transcript.messages.last.text, contains('没有待定补丁'));
    });
  });
}

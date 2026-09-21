// conatus_code — 基于 conatus 运行时的终端编码智能体

import 'dart:io';

import 'package:conatus/conatus.dart';
import 'package:conatus_coding/conatus_coding.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:conatus_tui/conatus_tui.dart';

Future<void> main(List<String> args) async {
  // ── 1. 创建根上下文 ──────────────────────────────────────────
  final app = Context.root(name: 'conatus_code');

  // ── 2. 基础设施 ─────────────────────────────────────────────
  provideLogger(app);
  final sessions = provideSessions(app);
  provideSessionPersistence(app);
  provideSessionLog(app);
  provideSessionLogRecorder(app);
  provideDatabase(app);
  provideDatabaseJson(app);

  // ── 3. 凭据与 LLM ───────────────────────────────────────────
  final credentials = provideCredentials(app);
  provideLlm(app, credentials: credentials);

  // ── 4. 能力接缝 ─────────────────────────────────────────────
  provideTools(app);
  provideShellLocal(app);
  provideFileSystemLocal(app);

  // ── 5. Agent 层 ─────────────────────────────────────────────
  final prompt = provideSystemPrompt(app);
  provideTimePrompt(app);
  provideMemory(app);
  provideCompaction(app);
  providePlanTool(app, session: sessions.create(id: 'default'));
  provideSpawnAgent(app);
  provideReflection(app);
  provideApproval(app, approval: AskUserApproval(
    askUser: app.require<AskUser>('askUser'),
  ));

  // ── 6. 可观测性 ─────────────────────────────────────────────
  provideTelemetry(app);
  instrumentTools(app);

  // ── 7. 任务中心 ─────────────────────────────────────────────
  provideTaskCenter(app);

  // ── 8. Coding 能力（conatus_code 的核心差异）────────────────
  // 文件工具：read_file / write_file / edit_file / rg / glob
  provideFsTools(app);

  // 代码执行：run_code 工具 + SubprocessCodeRuntime 后端
  provideCoding(
    app,
    codeRuntime: SubprocessCodeRuntime(
      shell: app.require<ShellExecutor>('shell'),
      executable: 'dart',
      extension: '.dart',
      baseArgs: const <String>['run'],
    ),
    enableRuntime: true,
  );

  // ── 9. 系统提示词 ───────────────────────────────────────────
  prompt.section(PromptSection(
    name: 'persona',
    order: 0,
    text: () => '你是一个编码助手，专注于读写代码、定位问题和执行验证。'
        '需要实时信息时调用工具；需要修改代码时先用 read_file 了解上下文。',
  ));

  // ── 10. Agent Loop ──────────────────────────────────────────
  final session = sessions.create(id: 'default');
  final agent = provideAgentLoop(app, session: session);

  // ── 11. 意图路由（可选）─────────────────────────────────────
  // 高频命令走本地匹配，未命中落回 Agent Loop
  final router = provideIntentRouter(app);
  router.register(Intent(
    name: 'read_file',
    description: '读取文件',
    patterns: <Pattern>[RegExp(r'^(读|cat|查看)\s+(.+)$')],
    action: ToolAction(
      tool: 'read_file',
      argsTemplate: <String, Object?>{'path': r'${1}'},
    ),
  ));

  // ── 12. 启动 TUI ────────────────────────────────────────────
  final tui = TuiApp(
    agent: agent,
    session: session,
    sessions: sessions,
    app: app,
  );

  // 退出时清理
  ProcessSignal.sigint.watch().listen((_) {
    tui.dispose();
    app.dispose();
    exit(0);
  });

  await tui.run();
}

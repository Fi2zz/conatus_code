/// headless 单轮执行：装配会话 Agent Loop、跑一轮、按格式输出。
///
/// 复用 `ConatusTuiRuntime` 的完整装配（工具 / 沙箱 / 搜索 / 技能 / MCP /
/// 压缩 / 记忆），只额外挂会话级 Agent Loop；不装 TUI 交互件（调用方以
/// `interactive: false` 创建 runtime）。沙箱与预算护栏照常生效。
library;

import 'dart:convert';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import '../tui/tui_app.dart';

/// headless 输出格式。
enum HeadlessFormat {
  /// 只打印回复文本。
  text,

  /// 单行 JSON：`reply` / `sessionId` / `exitCode`。
  json,
}

/// 一次 headless 执行的产出。
class HeadlessResult {
  const HeadlessResult({
    required this.exitCode,
    required this.reply,
    required this.sessionId,
  });

  /// 进程退出码（0 成功 / 1 轮次失败，由调用方映射异常）。
  final int exitCode;

  /// 模型最终回复。
  final String reply;

  /// 会话 id（供后续 `--session` 恢复）。
  final String sessionId;
}

/// 跑一轮并返回产出；调用方负责 `runtime.dispose()`。
///
/// [sessionId] 非空时恢复该会话（不存在的 id 由会话仓库懒建），否则新建。
Future<HeadlessResult> runHeadless(
  ConatusTuiRuntime runtime, {
  required String prompt,
  String? sessionId,
}) async {
  final Session session = sessionId == null
      ? runtime.sessions.create()
      : await runtime.sessions.open(sessionId);
  final Context ctx = runtime.app.plugin(
    'headless:${session.id}',
    (Context child) {
      provideAgentLoop(child, session: session, maxSteps: runtime.maxSteps);
    },
  );
  try {
    final AgentTurn turn = await ctx.agentLoop.run(prompt);
    return HeadlessResult(
      exitCode: 0,
      reply: turn.reply,
      sessionId: session.id,
    );
  } finally {
    ctx.dispose();
    await runtime.sessions.flush();
  }
}

/// 按 [format] 渲染结果（json 为单行，脚本可直接 `jq` 消费）。
String renderHeadless(HeadlessResult result, HeadlessFormat format) {
  if (format == HeadlessFormat.json) {
    return jsonEncode(<String, Object?>{
      'reply': result.reply,
      'sessionId': result.sessionId,
      'exitCode': result.exitCode,
    });
  }
  return result.reply;
}

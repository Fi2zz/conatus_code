/// autonomous runner 的会话级装配：独立 Agent Loop + costTracker 接线。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

/// 在会话上下文中装配 `'autonomousRunner'`。
///
/// - 用独立 [AgentLoop]（与主 loop 同 session，但不挂 goalDriver），避免与
///   Runner 自己的轮次记账双算；
/// - [provideAutonomousRunner] 从上下文的 `'costTracker'` 惰性解析预算缝
///   （`ConatusTuiRuntime.create` 已提供 `CostTrackerImpl`），预算统计与
///   审计随即生效。
AutonomousRunner provideAutonomous(
  Context ctx, {
  required Session session,
  int maxSteps = 8,
}) {
  final AgentLoop agent = AgentLoop(
    llm: composeLlm(
      ctx.require<LlmProvider>('llm'),
      telemetry: ctx.get<Telemetry>('telemetry'),
      cache: ctx.get<ContextCache>('contextCache'),
      recorder: ctx.get<SessionLogRecorder>('sessionLogRecorder'),
    ),
    tools: ctx.tools,
    session: session,
    systemPrompt: ctx.get<SystemPrompt>('systemPrompt'),
    compactor: ctx.get<CompactionEngine>('compaction'),
    memory: ctx.get<MemoryStore>('memory'),
    reflector: ctx.get<Reflector>('reflection'),
    maxSteps: maxSteps,
  );
  return provideAutonomousRunner(
    ctx,
    agent: agent,
    goal: ctx.goal,
    session: session,
  );
}

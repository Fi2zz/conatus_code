/// 内置 `general` 子 Agent：显式白名单允许 medium 写，仍排除 spawn / high。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _SchemaProvider implements LlmProvider {
  final List<List<Map<String, dynamic>>?> schemas =
      <List<Map<String, dynamic>>?>[];

  @override
  String get name => 'schema';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    schemas.add(tools);
    return const LlmResult(content: 'done', provider: 'schema', model: 'm');
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

Set<String> _names(List<Map<String, dynamic>>? schemas) => <String>{
  for (final Map<String, dynamic> schema
      in schemas ?? const <Map<String, dynamic>>[])
    schema['name'] as String,
};

void main() {
  test('general 白名单包含 medium 写工具，排除 spawn 与 high 工具', () async {
    final Context host = Context.root();
    addTearDown(host.dispose);
    final ToolRegistry tools = ToolRegistry();
    tools.fn(
      'write_file',
      riskLevel: ToolRisk.medium,
      handler: (ToolContext ctx) async => ToolResult.success('w'),
    );
    tools.fn(
      'run_command',
      riskLevel: ToolRisk.high,
      handler: (ToolContext ctx) async => ToolResult.success('r'),
    );
    tools.fn(
      'spawn_agent',
      handler: (ToolContext ctx) async => ToolResult.success('s'),
    );
    final Directory workdir = Directory.systemTemp.createTempSync(
      'nava-general-agent-',
    );
    addTearDown(() => workdir.deleteSync(recursive: true));
    final AgentRegistry registry = await AgentRegistry.load(
      workdir: workdir.path,
      home: '/nonexistent-nava-home',
    );
    final AgentProfileResolver resolver = AgentProfileResolver(
      registry: registry,
    );
    addTearDown(resolver.close);
    final _SchemaProvider provider = _SchemaProvider();
    final SpawnAgentTool spawn = SpawnAgentTool(
      host: host,
      llm: provider,
      tools: tools,
      profileResolver: resolver,
    );

    final ToolResult result = await spawn.call(
      const ToolContext(
        ToolCall(
          name: 'spawn_agent',
          arguments: <String, Object?>{'task': 'write', 'agent': 'general'},
        ),
      ),
    );

    expect(result.isError, isFalse);
    final Set<String> exposed = _names(provider.schemas.first);
    expect(exposed, contains('write_file'));
    expect(exposed, isNot(contains('spawn_agent')));
    expect(exposed, isNot(contains('run_command')));
  });
}

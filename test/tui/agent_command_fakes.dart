/// 命令测试替身：模型、假 task、可记录请求的 provider 注册表。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/providers.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 一次模型调用的现场快照。
class CapturedTurn {
  const CapturedTurn({
    required this.prompt,
    required this.agentId,
    required this.planModeActive,
  });

  /// 本轮最后一条用户消息。
  final String prompt;

  /// 调用发生时的 Agent ID。
  final String agentId;

  /// 调用发生时 Plan Mode 是否激活。
  final bool planModeActive;
}

/// 记录 prompt 并按脚本返回“完成。”的提供商。
class CommandCaptureProvider implements LlmProvider {
  /// 收到的调用。
  final List<CapturedTurn> turns = <CapturedTurn>[];

  /// 最近一次请求的 system prompt。
  String lastSystemPrompt = '';

  /// prompt 回调；装配后由 harness 记录调用时的 Agent / Plan Mode。
  void Function(String prompt)? onPrompt;

  /// 首次模型调用已开始。
  final Completer<void> started = Completer<void>();

  /// 非空时模型调用挂起，直到测试放行。
  Completer<void>? gate;

  @override
  String get name => 'capture';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    _record(messages);
    await _pause();
    return const LlmResult(content: '完成。', provider: 'capture', model: 'm');
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async* {
    _record(messages);
    await _pause();
    yield const LlmTextDelta('完成。');
    yield const LlmStreamDone(provider: 'capture', model: 'm');
  }

  Future<void> _pause() async {
    if (!started.isCompleted) started.complete();
    final Completer<void>? pending = gate;
    if (pending != null) await pending.future;
  }

  void _record(List<LlmMessage> messages) {
    for (final LlmMessage message in messages) {
      if (message.role == 'system') {
        lastSystemPrompt = message.content;
        break;
      }
    }
    onPrompt?.call(messages.isEmpty ? '' : messages.last.content);
  }

  @override
  void close() {}
}

/// 记录 `task` 调用的假工具。
class FakeSpawnTool extends Tool {
  /// 收到的参数。
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  /// 首次调用已开始。
  final Completer<void> started = Completer<void>();

  /// 非空时调用挂起，直到测试放行（模拟长时间子 Agent）。
  Completer<void>? gate;

  @override
  String get name => 'task';

  @override
  String get description => '假子 Agent';

  @override
  List<ParamSpec> get params => <ParamSpec>[
    ParamSpec.string('task', required: true),
    ParamSpec.string('agent'),
  ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    calls.add(<String, Object?>{
      'task': context.str('task'),
      'agent': context.string('agent'),
    });
    if (!started.isCompleted) started.complete();
    final Completer<void>? pending = gate;
    if (pending != null) await pending.future;
    return ToolResult.success('[fake-spawn] 已完成');
  }
}

/// 中风险副作用工具：Plan Mode 激活时应被拦截。
class FakeMutateTool extends Tool {
  /// 是否真正执行过。
  bool mutated = false;

  @override
  String get name => 'mutate';

  @override
  String get description => '假副作用工具';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  Future<ToolResult> call(ToolContext context) async {
    mutated = true;
    return ToolResult.success('已修改');
  }
}

/// 带模型请求记录的 provider 注册表（模型覆盖测试用）。
///
/// [models] 是 `provider → 模型清单`；所有请求返回固定 SSE 回复，并把请求体
/// 收集到返回的列表里。
(ProviderRegistry, List<http.Request>) buildRecordingRegistry(
  Map<String, List<String>> models,
) {
  final List<http.Request> requests = <http.Request>[];
  final http.Client client = MockClient((http.Request request) async {
    requests.add(request);
    return http.Response.bytes(
      utf8.encode(_sseReply),
      200,
      headers: <String, String>{
        'content-type': 'text/event-stream; charset=utf-8',
      },
    );
  });
  final ProviderRegistry registry = ProviderRegistry(
    profiles: <ProviderProfile>[
      for (final MapEntry<String, List<String>> entry in models.entries)
        ProviderProfile(
          name: entry.key,
          baseUrl: 'https://${entry.key}.example/v1',
          apiKey: 'k',
          models: entry.value,
        ),
    ],
    currentName: models.keys.first,
    client: client,
  );
  return (registry, requests);
}

/// 请求体里的模型名。
String requestModel(http.Request request) {
  final Object? body = jsonDecode(request.body);
  if (body is Map<String, dynamic>) return body['model'] as String? ?? '';
  return '';
}

const String _sseReply = '''
data: {"id":"1","object":"chat.completion","model":"m","choices":[{"index":0,"message":{"role":"assistant","content":"完成。"},"finish_reason":"stop"}]}

data: [DONE]
''';

/// 只读快照（`.opencode` 不变断言）。
List<String> snapshotTree(Directory root) {
  final List<String> entries = <String>[
    for (final FileSystemEntity entity in root.listSync(
      recursive: true,
      followLinks: false,
    ))
      if (entity is File)
        '${entity.path.substring(root.path.length)}:${entity.readAsStringSync()}',
  ]..sort();
  return entries;
}

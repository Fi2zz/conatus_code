/// MCP prompt → 斜杠命令：`/<server>:<prompt>`，执行时取 prompt 并提交文本。
///
/// prompt 的 `role` / `text` 被摊平成 `role: text` 段落（assistant 角色的语义
/// 近似成文本，见设计裁决）；参数按声明顺序从 `$1..` 填，支持引号分组。
library;

import 'package:conatus_mcp/conatus_mcp.dart';

import '../commands/command_definition.dart';
import '../commands/command_expander.dart';

/// 从 [registry] 的全部 server 生成 prompt 命令。
///
/// 只对握手时声明了 `prompts` 能力的 server 取列表：没有能力的 server 不产生
/// 命令，也不发 `prompts/list`。单台列表失败只是没有命令，不抛错——MCP 是
/// 外部进程，启动期不能因一台坏掉而中断装配。
Future<List<CommandDefinition>> loadMcpPromptCommands(
  McpRegistry registry,
) async {
  final List<CommandDefinition> commands = <CommandDefinition>[];
  for (final String server in registry.servers) {
    if (!_supportsPrompts(registry, server)) continue;
    final List<McpPrompt> prompts = await registry.listPrompts(server: server);
    for (final McpPrompt prompt in prompts) {
      if (prompt.name.trim().isEmpty) continue;
      commands.add(_commandFor(registry, server, prompt));
    }
  }
  return commands;
}

/// 该 server 是否在握手能力里声明了 prompts。
bool _supportsPrompts(McpRegistry registry, String server) =>
    registry.clientOf(server)?.serverInfo?.capabilities.prompts ?? false;

CommandDefinition _commandFor(
  McpRegistry registry,
  String server,
  McpPrompt prompt,
) => CommandDefinition(
  name: '$server:${prompt.name}',
  template: '',
  sourcePath: '',
  description: prompt.description ?? '',
  executor: (String args) => _renderPrompt(registry, server, prompt, args),
);

/// 取值并拼成可提交的文本；空消息返回空串（由调用方提示「没有内容」）。
Future<String> _renderPrompt(
  McpRegistry registry,
  String server,
  McpPrompt prompt,
  String args,
) async {
  final List<McpPromptMessage> messages = await registry.getPrompt(
    server: server,
    name: prompt.name,
    arguments: _promptArguments(prompt, args),
  );
  return <String>[
    for (final McpPromptMessage message in messages)
      '${message.role}: ${message.text}',
  ].join('\n\n');
}

/// 按声明顺序把位置参数填进 prompt 参数表；缺省位置为空串。
Map<String, String> _promptArguments(McpPrompt prompt, String rawArgs) {
  final List<String> tokens = tokenizeCommandArguments(rawArgs);
  final Map<String, String> arguments = <String, String>{};
  for (int index = 0; index < prompt.arguments.length; index++) {
    final String name = prompt.arguments[index].name.trim();
    if (name.isEmpty) continue;
    arguments[name] = index < tokens.length ? tokens[index] : '';
  }
  return arguments;
}

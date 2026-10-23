/// MCP prompt → 斜杠命令：`/<server>:<prompt>`，执行时取 prompt 并提交文本。
///
/// prompt 的 `role` / `text` 被摊平成 `role: text` 段落（assistant 角色的语义
/// 近似成文本，见设计裁决）；参数按声明顺序从 `$1..` 填，支持引号分组。
library;

import 'package:conatus_mcp/conatus_mcp.dart';

import '../commands/command_definition.dart';
import '../commands/command_expander.dart';
import '../commands/command_registry.dart';

/// `skill:` 是技能命令的保留命名空间；同名 server 的 prompt 会撞车。
const String kMcpReservedServerName = 'skill';

/// 从 [registry] 的全部 server 生成 prompt 命令。
///
/// 只对握手时声明了 `prompts` 能力的 server 取列表：没有能力的 server 不产生
/// 命令，也不发 `prompts/list`。单台列表失败只是没有命令，原因经 [onWarning]
/// 报出，不抛错——MCP 是外部进程，启动期不能因一台坏掉而中断装配。
///
/// 名为 [kMcpReservedServerName] 的 server 会被跳过：它的命令会落进技能命令
/// 的保留前缀，注册了也无法执行。
Future<List<CommandDefinition>> loadMcpPromptCommands(
  McpRegistry registry, {
  void Function(String message)? onWarning,
}) async {
  final List<CommandDefinition> commands = <CommandDefinition>[];
  for (final String server in registry.servers) {
    if (server == kMcpReservedServerName) {
      onWarning?.call('MCP server "$server" 与技能命令命名空间冲突，已跳过其 prompt');
      continue;
    }
    if (!_supportsPrompts(registry, server)) continue;
    final List<McpPrompt> prompts = await registry.listPrompts(server: server);
    final String? error = registry.lastErrorFor(server);
    if (error != null) {
      onWarning?.call('MCP server $server 的 prompts 列表失败：$error');
    }
    for (final McpPrompt prompt in prompts) {
      if (prompt.name.trim().isEmpty) continue;
      commands.add(_commandFor(registry, server, prompt));
    }
  }
  return commands;
}

/// 把 prompt 命令登记进 [registry]；已存在的同名命令（磁盘 / 内建）优先。
///
/// 返回实际新增的条数，供装配期诊断。
int registerMcpPromptCommands(
  CommandRegistry registry,
  Iterable<CommandDefinition> commands,
) {
  int added = 0;
  for (final CommandDefinition command in commands) {
    if (registry.byName(command.name) != null) continue;
    registry.add(command);
    added++;
  }
  return added;
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

/// 按声明顺序填位置参数：给了就传（空串也算给了）；没给时必填项补空串，
/// 可选项直接省略——服务端才能区分「没传」与「传了空」。
Map<String, String> _promptArguments(McpPrompt prompt, String rawArgs) {
  final List<String> tokens = tokenizeCommandArguments(rawArgs);
  final Map<String, String> arguments = <String, String>{};
  for (int index = 0; index < prompt.arguments.length; index++) {
    final McpPromptArgument argument = prompt.arguments[index];
    final String name = argument.name.trim();
    if (name.isEmpty) continue;
    if (index < tokens.length) {
      arguments[name] = tokens[index];
    } else if (argument.required) {
      arguments[name] = '';
    }
  }
  return arguments;
}

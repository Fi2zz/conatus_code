/// 自定义命令的运行时定义。
library;

/// 一条从 `.md` 命令文档或动态来源（MCP prompt 等）解析出的命令。
///
/// [template] 是 prompt 模板，[executor] 非空时优先于模板：动态命令直接按
/// 原始参数字符串求值，不再做占位符展开。
class CommandDefinition {
  /// 构造一条命令定义。
  const CommandDefinition({
    required this.name,
    required this.template,
    required this.sourcePath,
    this.description = '',
    this.agent,
    this.model,
    this.subagent = false,
    this.executor,
  });

  /// 命令 ID；嵌套目录用 `/` 连接，如 `team/review`。
  final String name;

  /// 菜单展示用描述；缺省为空串。
  final String description;

  /// prompt 模板正文；可为空（空命令只提示）。
  final String template;

  /// 执行前切换到的 agent 名称。
  final String? agent;

  /// 执行时临时使用的模型标识。
  final String? model;

  /// 是否以前台子 Agent 执行。
  final bool subagent;

  /// 来源文件路径（动态命令可为空串）。
  final String sourcePath;

  /// 动态执行体；非空时优先于 [template]。
  final Future<String> Function(String args)? executor;
}

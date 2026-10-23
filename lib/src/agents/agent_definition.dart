/// 自定义 Agent 的运行时定义。
library;

import 'package:conatus_agent/conatus_agent.dart' show PermissionRule;

/// Agent 的使用范围。
enum AgentMode {
  /// 可作为主会话 Agent。
  primary,

  /// 只能作为子 Agent。
  subagent,

  /// 两者皆可。
  all;

  /// 解析 frontmatter 里的字面量；未知值抛 [FormatException]。
  static AgentMode parse(String value) => switch (value.trim()) {
    'primary' => AgentMode.primary,
    'subagent' => AgentMode.subagent,
    'all' => AgentMode.all,
    _ => throw const FormatException('字段 mode 必须是 primary/subagent/all'),
  };
}

/// 一份从 `.md` Agent 文档解析出的定义。
///
/// [system] 是文档正文（系统提示），[permissions] 是 Agent 自带的权限规则，
/// 由调用方追加到全局规则之后。内置 Agent 的 [sourcePath] 以 `builtin:` 开头。
class AgentDefinition {
  /// 构造一份 Agent 定义。
  const AgentDefinition({
    required this.id,
    required this.sourcePath,
    this.description = '',
    this.mode = AgentMode.primary,
    this.system = '',
    this.model,
    this.steps,
    this.tools,
    this.permissions = const <PermissionRule>[],
    this.hidden = false,
    this.color,
  });

  /// Agent ID；嵌套目录用 `/` 连接，如 `team/reviewer`。
  final String id;

  /// 菜单展示用描述；可为空。
  final String description;

  /// 主会话 / 子 Agent / 两者皆可。
  final AgentMode mode;

  /// 系统提示正文。
  final String system;

  /// 模型标识（`provider/model`）；`null` 表示沿用当前模型。
  final String? model;

  /// 单轮最大步数；`null` 表示沿用全局配置。
  final int? steps;

  /// 工具白名单；`null` 表示不额外限制。
  final List<String>? tools;

  /// Agent 自带权限规则；追加在全局规则之后。
  final List<PermissionRule> permissions;

  /// 是否从选择器与子 Agent 目录隐藏（仍可按 ID 解析）。
  final bool hidden;

  /// 展示颜色（如 `#ff6b6b`）；`null` 表示用主题默认色。
  final String? color;

  /// 来源文件路径；内置 Agent 为 `builtin:<id>`。
  final String sourcePath;
}

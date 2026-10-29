/// `/doctor` 的检查聚合：只读体检各项装配，供用户自查。
library;

import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_mcp/conatus_mcp.dart';

import '../../providers.dart';
import '../agents/agent_registry.dart';
import '../agents/agent_resolver.dart';
import '../budget/cost_tracker.dart';
import '../commands/command_registry.dart';
import '../permissions/permission_wiring.dart';
import '../tools/guarded_shell.dart';

/// 一项体检结果。
class DoctorCheck {
  const DoctorCheck({
    required this.name,
    required this.ok,
    this.warning = false,
    this.hint,
  });

  /// 检查项名。
  final String name;

  /// 是否通过。
  final bool ok;

  /// 未通过但非阻塞（`⚠`）；缺省按 `✗` 处理。
  final bool warning;

  /// 修复提示。
  final String? hint;
}

/// 聚合体检项（全部只读）。
List<DoctorCheck> doctorChecks(Context app) => <DoctorCheck>[
  DoctorCheck(
    name: '配置文件',
    ok: app.has('configPath'),
    hint: '未定位到 config.toml（--config 未指定）',
  ),
  _providerCheck(app),
  _llmChainCheck(app),
  _modelProfileCheck(app),
  _mcpCheck(app),
  DoctorCheck(
    name: '工具表',
    ok: (app.get<ToolRegistry>('tools')?.names.isNotEmpty) ?? false,
    hint: '工具未装配',
  ),
  _shellCheck(app),
  _permissionCheck(app),
  _discoveryCheck(app),
  _configDeprecationCheck(app),
  DoctorCheck(name: 'rg', ok: _rgAvailable(), hint: 'PATH 里没有 rg（搜索工具会降级/报错）'),
];

/// Agent / 命令发现的跳过项与 Agent 模型回退。
///
/// 这些告警此前只存在于注册表里，用户看不到坏掉的 `.md` 或写错的 `model:`；
/// 这里把来源文件与原因一起报出来（最多 3 条 + 总数）。
DoctorCheck _discoveryCheck(Context app) {
  final List<String> warnings = <String>[
    ...?app.get<AgentRegistry>('agentRegistry')?.warnings,
    ...?app.get<CommandRegistry>('commandRegistry')?.warnings,
    ...?app.get<AgentProfileResolver>('agentProfiles')?.warnings,
  ];
  if (warnings.isEmpty) {
    return const DoctorCheck(name: 'Agent / 命令发现', ok: true, hint: '无告警');
  }
  final String head = warnings.take(3).join('；');
  final String more = warnings.length > 3
      ? '（另有 ${warnings.length - 3} 条）'
      : '';
  return DoctorCheck(
    name: 'Agent / 命令发现',
    ok: false,
    warning: true,
    hint: '$head$more',
  );
}

DoctorCheck _configDeprecationCheck(Context app) {
  final List<String> warnings =
      app.get<List<String>>('configWarnings') ?? const <String>[];
  if (warnings.isEmpty) {
    return const DoctorCheck(name: '配置废弃项', ok: true, hint: '无');
  }
  final String head = warnings.take(3).join('；');
  final String more = warnings.length > 3
      ? '（另有 ${warnings.length - 3} 条）'
      : '';
  return DoctorCheck(
    name: '配置废弃项',
    ok: false,
    warning: true,
    hint: '$head$more',
  );
}

DoctorCheck _providerCheck(Context app) {
  final ProviderRegistry? registry = app.get<ProviderRegistry>('providers');
  if (registry != null && registry.profiles.isNotEmpty) {
    return DoctorCheck(
      name: '模型提供商',
      ok: true,
      hint: '${registry.profiles.length} 个',
    );
  }
  return const DoctorCheck(
    name: '模型提供商',
    ok: false,
    hint: '无已配置 provider：/provider add 或编辑 config.toml [providers.*]',
  );
}

/// LLM 链：候选数与最近一次回退。
///
/// 回退是静默发生的——没有这项，用户只会看到回答风格突然变了，却不知道
/// 主模型已经挂过一次。
DoctorCheck _llmChainCheck(Context app) {
  final LlmChain? chain = app.get<LlmChainSlot>('llmChainSlot')?.current;
  if (chain == null) {
    return const DoctorCheck(
      name: '模型回退链',
      ok: false,
      hint: '未装配（先用 /provider 配置提供商）',
    );
  }
  return DoctorCheck(
    name: '模型回退链',
    ok: true,
    warning: chain.entries.length < 2,
    hint: _chainHint(chain, app.get<LlmNotices>('llmNotices')),
  );
}

String _chainHint(LlmChain chain, LlmNotices? notices) {
  final StringBuffer buffer = StringBuffer(
    '${chain.entries.length} 个候选：${chain.entries.join(' → ')}',
  );
  final LlmFallbackEvent? last = notices?.lastFallback;
  if (last != null) {
    buffer.write('；最近回退 ${last.fromProvider} → ${last.toProvider}');
  }
  if (chain.skipped.isNotEmpty) {
    buffer.write(
      '；已跳过 ${chain.skipped.length} 条无效回退'
      '（${chain.skipped.keys.join('、')}）',
    );
  }
  return buffer.toString();
}

DoctorCheck _mcpCheck(Context app) {
  final McpRegistry? mcp = app.get<McpRegistry>('mcp');
  if (mcp != null && mcp.servers.isNotEmpty) {
    return DoctorCheck(
      name: 'MCP server',
      ok: true,
      warning: true,
      hint: '${mcp.servers.length} 个',
    );
  }
  return const DoctorCheck(
    name: 'MCP server',
    ok: false,
    warning: true,
    hint: '未配置（config.toml [mcp.servers.*]）',
  );
}

/// 上下文窗口与费率（models.dev）；拿不到就说未知，不猜。
DoctorCheck _modelProfileCheck(Context app) {
  final CostTrackerImpl? tracker = app.get<CostTrackerImpl>('costTracker');
  final ModelProfile? profile = tracker?.profile;
  if (tracker == null) {
    return const DoctorCheck(
      name: '模型窗口 / 费率',
      ok: false,
      warning: true,
      hint: '未装配 costTracker',
    );
  }
  if (profile == null) {
    return DoctorCheck(
      name: '模型窗口 / 费率',
      ok: false,
      warning: true,
      hint:
          '${tracker.provider}/${tracker.model}：models.dev 无此记录'
          '（上下文未知、费率按 0 计）',
    );
  }
  return DoctorCheck(
    name: '模型窗口 / 费率',
    ok: true,
    warning: !profile.hasContext || !profile.hasPricing,
    hint:
        '窗口 ${profile.hasContext ? '${profile.contextLength ~/ 1000}k' : '未知'}'
        ' · ${profile.rateSummary}',
  );
}

DoctorCheck _shellCheck(Context app) {
  final ShellExecutor? shell = app.get<ShellExecutor>('shell');
  if (shell is GuardedShellExecutor) {
    return const DoctorCheck(name: '命令审查', ok: true, hint: 'shape scan 生效');
  }
  return const DoctorCheck(
    name: '命令审查',
    ok: true,
    warning: true,
    hint: '未装配（命令不经 shape scan）',
  );
}

/// 权限规则载入状态：`permissions.json` 坏掉时 deny 会静默失效，必须让
/// `/doctor` 说出来（启动系统提示另有一份，见 `tui_app.dart`）。
DoctorCheck _permissionCheck(Context app) {
  final PermissionWiring? wiring = app.get<PermissionWiring>(
    'permissionWiring',
  );
  if (wiring == null) {
    return const DoctorCheck(name: '权限规则', ok: true, hint: '未装配');
  }
  final String? error = wiring.loadError;
  if (error != null) {
    return DoctorCheck(name: '权限规则', ok: false, warning: true, hint: error);
  }
  if (wiring.skippedRules > 0) {
    return DoctorCheck(
      name: '权限规则',
      ok: false,
      warning: true,
      hint: '${wiring.skippedRules} 条规则非法已跳过（permissions.json）',
    );
  }
  return DoctorCheck(
    name: '权限规则',
    ok: true,
    hint: '${wiring.rules.length} 条生效',
  );
}

bool _rgAvailable() {
  final String? path = Platform.environment['PATH'];
  if (path == null) return false;
  for (final String dir in path.split(':')) {
    if (dir.isEmpty) continue;
    if (File('$dir${Platform.pathSeparator}rg').existsSync()) return true;
  }
  return false;
}

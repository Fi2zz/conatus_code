/// `/doctor` 的检查聚合：只读体检各项装配，供用户自查。
library;

import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_mcp/conatus_mcp.dart';

import '../../providers.dart';
import '../budget/cost_tracker.dart';
import '../sandbox/jailed_file_system.dart';
import '../sandbox/rejecting_shell.dart';
import '../sandbox/sandboxed_shell.dart';

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
      _fsCheck(app),
      DoctorCheck(
        name: 'rg',
        ok: _rgAvailable(),
        hint: 'PATH 里没有 rg（搜索工具会降级/报错）',
      ),
    ];

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
  final LlmChain? chain = app.get<LlmChain>('llmChain');
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
  final StringBuffer buffer =
      StringBuffer('${chain.entries.length} 个候选：${chain.entries.join(' → ')}');
  final LlmFallbackEvent? last = notices?.lastFallback;
  if (last != null) {
    buffer.write('；最近回退 ${last.fromProvider} → ${last.toProvider}');
  }
  if (chain.skipped.isNotEmpty) {
    buffer.write('；已跳过 ${chain.skipped.length} 条无效回退'
        '（${chain.skipped.keys.join('、')}）');
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
      hint: '${tracker.provider}/${tracker.model}：models.dev 无此记录'
          '（上下文未知、费率按 0 计）',
    );
  }
  return DoctorCheck(
    name: '模型窗口 / 费率',
    ok: true,
    warning: !profile.hasContext || !profile.hasPricing,
    hint: '窗口 ${profile.hasContext ? '${profile.contextLength ~/ 1000}k' : '未知'}'
        ' · ${profile.rateSummary}',
  );
}

DoctorCheck _shellCheck(Context app) {
  final ShellExecutor? shell = app.get<ShellExecutor>('shell');
  if (shell is SandboxedShellExecutor) {
    return const DoctorCheck(name: 'OS 沙箱（Layer 2）', ok: true);
  }
  if (shell is RejectingShellExecutor) {
    return const DoctorCheck(
      name: 'OS 沙箱（Layer 2）',
      ok: false,
      hint: '沙箱后端不可用，命令执行已禁用（[sandbox] enabled=false 可关闭）',
    );
  }
  return const DoctorCheck(
    name: 'OS 沙箱（Layer 2）',
    ok: true,
    warning: true,
    hint: '未启用（本地直执）',
  );
}

DoctorCheck _fsCheck(Context app) {
  final FileSystem? fs = app.get<FileSystem>('fs');
  final bool jailed = fs is JailedFileSystem;
  return DoctorCheck(
    name: '文件 jail（Layer 1）',
    ok: true,
    warning: !jailed,
    hint: jailed ? '生效' : '未启用（fs_jail=false）',
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

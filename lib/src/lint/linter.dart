/// lint-on-edit：模型编辑文件后自动跑 linter，把告警塞回工具结果。
///
/// 服务键 `'linter'`。linter 命令按项目类型探测（`[lint] command` 可覆盖），
/// 带去抖窗口（缺省 10s）避免连续编辑连跑；告警截断（[kLintFeedbackChars]）
/// 追加进编辑工具的结果，模型当场看到并修复。执行走 `'shell'` 缝（沙箱）。
library;

import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import '../config/config_schema.dart';

/// 告警反馈的截断字符数（取尾部）。
const int kLintFeedbackChars = 2000;

/// 触发 lint 的编辑工具。
const Set<String> kLintToolNames = <String>{
  'write_file',
  'edit_file',
  'apply_patch',
};

/// lint-on-edit 服务。
class LinterService {
  LinterService({
    required ShellExecutor shell,
    required LintConfig config,
    required String workdir,
  })  : _shell = shell,
        _config = config,
        _workdir = workdir;

  final ShellExecutor _shell;
  final LintConfig _config;
  final String _workdir;
  String? _command;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);

  /// 探测出的 linter 命令（`[lint] command` 覆盖优先）；无则 `null`。
  String? get command => _command;

  /// 首次调用时按项目类型探测 linter 命令。
  String? _resolveCommand() {
    final String? override = _config.command;
    if (override != null) return override;
    final String sep = Platform.pathSeparator;
    if (File('$_workdir${sep}pubspec.yaml').existsSync()) return 'dart analyze';
    if (File('$_workdir${sep}go.mod').existsSync()) return 'go vet ./...';
    if (File('$_workdir${sep}Cargo.toml').existsSync()) return 'cargo check';
    if (File('$_workdir${sep}package.json').existsSync()) return 'eslint .';
    return null;
  }

  /// 去抖窗口内返回 `null`；否则跑 linter 返回告警文本（截断、可空）。
  Future<String?> runIfDue() async {
    if (!_config.enabled) return null;
    final String? command = _command ??= _resolveCommand();
    if (command == null) return null;
    final DateTime now = DateTime.now();
    final int debounce = _config.debounceSeconds;
    if (debounce > 0 && now.difference(_lastRun).inSeconds < debounce) {
      return null;
    }
    _lastRun = now;
    final ShellRunResult result;
    try {
      result = await _shell.run(_shell.resolve(ShellExecRequest(
        command: command,
        workdir: _workdir,
        timeoutMs: kLintTimeoutMs,
      )));
    } catch (_) {
      return null; // linter 缺失/执行异常：静默跳过
    }
    if (result.timedOut || result.exitCode == 0) return null;
    final String text = '${result.stdout.text}\n${result.stderr.text}'.trim();
    if (text.isEmpty) return null;
    return text.length > kLintFeedbackChars
        ? text.substring(text.length - kLintFeedbackChars)
        : text;
  }

  /// 挂工具中间件：编辑工具成功返回后跑 lint 并追加告警。
  Disposer mount(ToolRegistry tools) {
    if (!_config.enabled) return () {};
    return tools.use((ToolCall call, Future<ToolResult> Function() next) async {
      final ToolResult result = await next();
      if (result.isError || !kLintToolNames.contains(call.name)) return result;
      final String? warnings = await runIfDue();
      if (warnings == null) return result;
      return ToolResult.success(
        '${result.content}\n\n[Lint] 检测到告警：\n$warnings',
        value: result.value,
      );
    });
  }
}

/// lint 命令超时（毫秒）。
const int kLintTimeoutMs = 30000;

/// 装配：注册 `'linter'` 服务并挂中间件。
LinterService provideLinter(
  Context ctx, {
  required LintConfig config,
  required String workdir,
  ShellExecutor? shell,
  ToolRegistry? tools,
}) {
  final LinterService linter = LinterService(
    shell: shell ?? ctx.require<ShellExecutor>('shell'),
    config: config,
    workdir: workdir,
  );
  ctx.provide('linter', linter);
  ctx.effect(() => linter.mount(tools ?? ctx.tools));
  return linter;
}
